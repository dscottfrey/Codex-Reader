//
//  PaginatedChapterView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The SwiftUI bridge to `UIPageViewController` for the two paginated
//  page-turn styles — Curl and Slide. Per Rendering directive §2.5,
//  both use the same `UIPageViewController` with only the
//  `transitionStyle` differing. Scroll mode lives in WKWebViewWrapper.
//
//  WHAT THIS COMPOSES:
//  - A `UIPageViewController` whose pages are `PageImageVC` instances.
//    Each VC shows one pre-rendered page UIImage pulled from
//    `PageImageCache`.
//  - A coordinator that acts as the page view controller's data source
//    and delegate, and observes `.codexPageRendered` notifications so
//    a VC whose image hadn't landed in the cache at creation time can
//    receive it later.
//
//  WHY UIImage, NOT WKWebView:
//  Per Rendering directive §3.3+, paginated modes display pre-rendered
//  page images, not live WebViews. The bake happens once in
//  ChapterPageRenderer's off-screen WKWebView. Display is then a
//  static UIImageView, which UIPageViewController can curl/slide
//  cheaply because each "page" is just an image. This file used to
//  host live WKWebViews per page (via ChapterPageVC); that design
//  was retired in Milestone A — see Docs/HANDOFF.md §4.
//
//  CHAPTER BOUNDARIES:
//  When the data source would return a page beyond the chapter, it
//  returns nil. UIPageViewController's built-in swipe then stops at
//  the boundary. `ReaderView`'s tap-zone handlers detect a boundary
//  hit via the pagination engine and trigger a chapter swap — which
//  rebuilds this whole view for the new chapter.
//
//  CACHE MISSES:
//  When a `PageImageVC` is created for a page that isn't yet cached
//  (the renderer is still working on it), the VC starts blank. The
//  underlying SwiftUI surface paints the theme's background colour,
//  so the user sees a uniform blank page rather than a system white
//  rectangle. When the page lands in the cache, ReaderViewModel posts
//  `.codexPageRendered`; the coordinator finds the live VC for that
//  (chapterHref, pageIndex) and sets its image. Refresh is
//  imperceptible — UIImageView assignment is synchronous.
//

import SwiftUI
import UIKit

/// Wraps a UIPageViewController for the current chapter. Rebuilt
/// whenever the chapter URL or transition style changes.
struct PaginatedChapterView: UIViewControllerRepresentable {

    // MARK: - Inputs

    /// Chapter href — the canonical chapter identifier the cache and
    /// the spine use. Together with `pageIndex` it uniquely keys an
    /// image in the cache.
    let chapterHref: String

    let transitionStyle: UIPageViewController.TransitionStyle

    /// Which page to land on when this view first appears.
    let initialPageIndex: Int

    /// Total pages in this chapter. Sourced from the pagination
    /// engine after `ChapterPageRenderer.loadChapter` returns; the
    /// data source uses it to clamp swipes at the boundary.
    let totalPages: Int

    /// The shared image cache — every coordinator pulls from this.
    let pageImageCache: PageImageCache

    let onPageChanged: (Int) -> Void

    /// Fires once with the coordinator — ReaderView holds a weak
    /// reference for tap-zone-driven turns.
    let onControllerReady: (Coordinator) -> Void

    /// Reports how many pages the UIPageViewController is showing at
    /// once (1 = single-page; 2 = the iPad-landscape open-book
    /// spread). The pagination engine uses this to compute chapter
    /// boundaries correctly.
    let onVisiblePagesChanged: (Int) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPageChanged: onPageChanged,
            onVisiblePagesChanged: onVisiblePagesChanged
        )
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear

        context.coordinator.pageViewController = pvc
        context.coordinator.configure(with: self)

        let initial = context.coordinator.makePageVC(pageIndex: initialPageIndex)
        pvc.setViewControllers(
            [initial],
            direction: .forward,
            animated: false,
            completion: nil
        )
        context.coordinator.currentPage = initialPageIndex
        onControllerReady(context.coordinator)
        return pvc
    }

    func updateUIViewController(
        _ pvc: UIPageViewController,
        context: Context
    ) {
        context.coordinator.configure(with: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject,
                             UIPageViewControllerDataSource,
                             UIPageViewControllerDelegate {

        private let onPageChanged: (Int) -> Void
        private let onVisiblePagesChanged: (Int) -> Void

        weak var pageViewController: UIPageViewController?

        // Configured by `configure(with:)` on every SwiftUI update.
        private var chapterHref: String?
        private var totalPages: Int = 1
        private var cache: PageImageCache?

        /// Weak registry of every `PageImageVC` we've handed UIKit for
        /// the current chapter. UIPageViewController caches ~3 alive
        /// at once but doesn't expose them; we keep our own weak refs
        /// so a late-arriving "page rendered" notification can find
        /// the VC waiting on its image and update it.
        private let liveVCs = NSHashTable<PageImageVC>.weakObjects()

        var currentPage: Int = 1

        init(
            onPageChanged: @escaping (Int) -> Void,
            onVisiblePagesChanged: @escaping (Int) -> Void
        ) {
            self.onPageChanged = onPageChanged
            self.onVisiblePagesChanged = onVisiblePagesChanged
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageRendered(_:)),
                name: .codexPageRendered,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func configure(with wrapper: PaginatedChapterView) {
            self.chapterHref = wrapper.chapterHref
            self.totalPages  = max(1, wrapper.totalPages)
            self.cache       = wrapper.pageImageCache
        }

        /// Build a `PageImageVC` for the current chapter at the given
        /// 1-based pageIndex. Pulls the cached image if present; else
        /// the VC begins blank and refreshes when the page-rendered
        /// notification fires.
        func makePageVC(pageIndex: Int) -> PageImageVC {
            guard let chapterHref else {
                // Defensive — configure() should always have run before
                // any data-source call. If not, return an empty VC
                // rather than crashing.
                return PageImageVC(
                    chapterHref: "",
                    pageIndex: pageIndex,
                    initialImage: nil
                )
            }
            return makePageVC(chapterHref: chapterHref, pageIndex: pageIndex)
        }

        /// Build a PageImageVC for an arbitrary chapter — used by the
        /// spine extension when it needs to construct cross-chapter
        /// pages (the right-hand page of an iPad landscape spread can
        /// be either this chapter or the next).
        func makePageVC(chapterHref: String, pageIndex: Int) -> PageImageVC {
            let initial = cache?.image(forChapter: chapterHref, page: pageIndex)
            let vc = PageImageVC(
                chapterHref: chapterHref,
                pageIndex: pageIndex,
                initialImage: initial
            )
            liveVCs.add(vc)
            return vc
        }

        /// Forward visible-page-count changes up to the pagination
        /// engine. Exposed as a method so the spine extension (in a
        /// sibling file) can call it without needing access to the
        /// private `onVisiblePagesChanged` closure directly.
        func reportVisiblePagesChanged(_ count: Int) {
            onVisiblePagesChanged(count)
        }

        /// Imperatively turn to the next or previous page (or spread).
        /// Called by ReaderView's tap zones. No-op at chapter
        /// boundaries — ReaderView detects those via the pagination
        /// engine and triggers a chapter swap instead.
        ///
        /// In a two-page spread (iPad landscape Page Curl) the step
        /// is 2 pages; UIPageViewController requires
        /// `setViewControllers` to be called with both sides of the
        /// new spread.
        func turnPage(direction: UIPageViewController.NavigationDirection) {
            guard let pvc = pageViewController,
                  let currentVCs = pvc.viewControllers,
                  let currentLeft = currentVCs.first as? PageImageVC
            else { return }

            let isSpread = pvc.isDoubleSided && currentVCs.count == 2
            let step = isSpread ? 2 : 1

            let nextLeftIndex: Int
            switch direction {
            case .forward:
                let proposed = currentLeft.pageIndex + step
                guard proposed <= totalPages else { return }
                nextLeftIndex = proposed
            case .reverse:
                let proposed = currentLeft.pageIndex - step
                guard proposed >= 1 else { return }
                nextLeftIndex = proposed
            @unknown default:
                return
            }

            let newVCs: [UIViewController]
            if isSpread {
                let newLeft  = makePageVC(pageIndex: nextLeftIndex)
                let newRight = makePageVC(pageIndex: nextLeftIndex + 1)
                newVCs = [newLeft, newRight]
            } else {
                newVCs = [makePageVC(pageIndex: nextLeftIndex)]
            }

            pvc.setViewControllers(
                newVCs,
                direction: direction,
                animated: true,
                completion: { [weak self] _ in
                    self?.currentPage = nextLeftIndex
                    self?.onPageChanged(nextLeftIndex)
                }
            )
        }

        // MARK: Data source

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PageImageVC,
                  vc.pageIndex > 1 else { return nil }
            return makePageVC(pageIndex: vc.pageIndex - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PageImageVC,
                  vc.pageIndex < totalPages else { return nil }
            return makePageVC(pageIndex: vc.pageIndex + 1)
        }

        // MARK: Delegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard finished, completed,
                  let current = pageViewController.viewControllers?.first
                    as? PageImageVC
            else { return }
            currentPage = current.pageIndex
            onPageChanged(currentPage)
        }

        // MARK: - Late-render notification

        /// Fires when ReaderViewModel has just put a UIImage into the
        /// cache. If a live VC is currently waiting on that image
        /// (created blank because the cache missed at the time), set
        /// its image now.
        @objc private func handlePageRendered(_ notification: Notification) {
            // Hop to main — NotificationCenter delivers on the posting
            // queue, but every ReaderViewModel post happens on main, so
            // this is paranoia. Cheap.
            Task { @MainActor [weak self] in
                guard let self,
                      let userInfo = notification.userInfo,
                      let chapterHref = userInfo[CodexNotificationKey.chapterHref] as? String,
                      let pageIndex   = userInfo[CodexNotificationKey.pageIndex] as? Int,
                      let image       = self.cache?.image(
                        forChapter: chapterHref, page: pageIndex)
                else { return }

                for vc in self.liveVCs.allObjects
                where vc.chapterHref == chapterHref && vc.pageIndex == pageIndex {
                    vc.pageImage = image
                }
            }
        }
    }
}
