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
//  - A `UIPageViewController` whose pages are `ChapterPageVC` instances,
//    one per chapter page.
//  - A coordinator that acts as the page view controller's data source,
//    delegate, and the shared `WKScriptMessageHandler` for every
//    page's JavaScript bridge.
//
//  CHAPTER BOUNDARIES:
//  When the data source would return a page beyond the chapter, it
//  returns nil. UIPageViewController's built-in swipe then stops at
//  the boundary. `ReaderView`'s tap-zone handlers detect a boundary
//  hit via the pagination engine and trigger a chapter swap — which
//  rebuilds this whole view for the new chapter.
//
//  TAP-ZONE TURNS:
//  The wrapper exposes its coordinator via `onControllerReady` so the
//  ReaderView's tap zones can call `turnPage(direction:)`, which calls
//  `UIPageViewController.setViewControllers(_:direction:animated:)`
//  and runs the same curl/slide animation a swipe would.
//
//  LIVE SETTINGS UPDATES — KNOWN LIMITATION:
//  When the user changes a setting mid-read, the scripts are rebuilt
//  on every `updateUIViewController`, but UIKit does not give us
//  access to neighbour page VCs that UIPageViewController has cached
//  internally. We update the currently-visible VC live; neighbours
//  pick up the new styling the next time the user swipes into them.
//  TODO: keep a weak registry of all live ChapterPageVCs so live
//  updates reach every cached neighbour.
//

import SwiftUI
@preconcurrency import WebKit

/// Wraps a UIPageViewController for the current chapter. Rebuilt
/// whenever the chapter URL or transition style changes.
struct PaginatedChapterView: UIViewControllerRepresentable {

    // MARK: - Inputs

    let chapterURL: URL
    let readAccessURL: URL
    let transitionStyle: UIPageViewController.TransitionStyle

    /// File URL of the FIRST page of the next chapter in the spine, if
    /// one exists. Used when an iPad-landscape Page Curl spread needs
    /// a right-hand page but this chapter has run out of pages — we
    /// fill that right-hand slot with the next chapter's page 1 so the
    /// reader sees continuous content instead of a duplicate filler.
    /// nil for the last chapter in the spine.
    let nextChapterURL: URL?

    /// Which page to land on when this view first appears.
    let initialPageIndex: Int

    /// Total pages in this chapter, as known to the view model.
    let totalPages: Int

    let userScript: WKUserScript
    let paginationScript: WKUserScript

    /// The live CSS string, used to push live-update JS into the
    /// currently-visible page's WebView when the user changes a
    /// setting mid-read.
    let liveCSS: String

    let onPaginationMessage: (PaginationMessage) -> Void
    let onPageChanged: (Int) -> Void

    /// Fires once with the coordinator — ReaderView holds a weak
    /// reference for tap-zone-driven turns and live updates.
    let onControllerReady: (Coordinator) -> Void

    /// Reports how many pages the UIPageViewController is showing at
    /// once (1 = single-page; 2 = the iPad-landscape open-book
    /// spread). The pagination engine uses this to compute chapter
    /// boundaries correctly — on a two-page spread the right page is
    /// one further along than the "current" (left) page index.
    let onVisiblePagesChanged: (Int) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPaginationMessage: onPaginationMessage,
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
                             UIPageViewControllerDelegate,
                             WKScriptMessageHandler {

        private let onPaginationMessage: (PaginationMessage) -> Void
        private let onPageChanged: (Int) -> Void
        private let onVisiblePagesChanged: (Int) -> Void

        weak var pageViewController: UIPageViewController?

        private var chapterURL: URL?
        private var readAccessURL: URL?
        private var totalPages: Int = 1
        private var userScript: WKUserScript?
        private var paginationScript: WKUserScript?
        private var lastCSS: String = ""
        /// First-page URL of the next chapter, used to fill the right
        /// half of an iPad-landscape spread when this chapter runs out
        /// of pages. See PaginatedChapterView.nextChapterURL.
        private var nextChapterURL: URL?

        /// Weak registry of every ChapterPageVC we've created for this
        /// chapter. UIPageViewController caches ~3 alive at once but
        /// doesn't expose them publicly — we keep our own weak refs
        /// so incoming JS messages can be routed to the VC whose
        /// WebView sent them, and so live CSS updates can reach every
        /// cached neighbour (not just the visible VC).
        private let liveVCs = NSHashTable<ChapterPageVC>.weakObjects()

        var currentPage: Int = 1

        init(
            onPaginationMessage: @escaping (PaginationMessage) -> Void,
            onPageChanged: @escaping (Int) -> Void,
            onVisiblePagesChanged: @escaping (Int) -> Void
        ) {
            self.onPaginationMessage = onPaginationMessage
            self.onPageChanged = onPageChanged
            self.onVisiblePagesChanged = onVisiblePagesChanged
        }

        func configure(with wrapper: PaginatedChapterView) {
            self.chapterURL = wrapper.chapterURL
            self.readAccessURL = wrapper.readAccessURL
            self.totalPages = max(1, wrapper.totalPages)
            self.userScript = wrapper.userScript
            self.paginationScript = wrapper.paginationScript
            self.nextChapterURL = wrapper.nextChapterURL

            // Live CSS update — push to every live page VC, not just
            // the currently-visible one, so UIKit's cached neighbours
            // pick up the new styling before they're swiped into.
            if wrapper.liveCSS != lastCSS {
                lastCSS = wrapper.liveCSS
                let js = UserScriptBuilder.liveUpdateJS(css: wrapper.liveCSS)
                for vc in liveVCs.allObjects {
                    vc.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        func makePageVC(pageIndex: Int) -> ChapterPageVC {
            return makePageVC(
                chapterURL: chapterURL!,
                readAccessURL: readAccessURL!,
                pageIndex: pageIndex
            )
        }

        /// Build a ChapterPageVC for a chapter URL that may differ
        /// from the wrapper's current chapter. Used when a spread's
        /// right-hand slot needs to spill over into the next chapter
        /// (so a 1-page chapter doesn't render as a duplicate-on-both-
        /// columns spread). Same scripts and message handler are
        /// reused — the new VC's JS reports back through the same
        /// channel and the message handler's `senderChapterPageVC`
        /// matching keeps routing per-VC.
        func makePageVC(
            chapterURL: URL,
            readAccessURL: URL,
            pageIndex: Int
        ) -> ChapterPageVC {
            let vc = ChapterPageVC(
                chapterURL: chapterURL,
                readAccessURL: readAccessURL,
                pageIndex: pageIndex,
                userScript: userScript!,
                paginationScript: paginationScript!,
                messageHandler: self
            )
            // Register the VC weakly so incoming JS messages can be
            // routed back to it without keeping it alive past UIKit's
            // own release of the page.
            liveVCs.add(vc)
            return vc
        }

        /// Forward visible-page-count changes up to the pagination
        /// engine. Exposed as a method so the spine-location extension
        /// (in a sibling file) can call it without needing access to
        /// the private `onVisiblePagesChanged` closure directly.
        func reportVisiblePagesChanged(_ count: Int) {
            onVisiblePagesChanged(count)
        }

        /// Imperatively turn to the next or previous page (or spread).
        /// Called by ReaderView's tap zones. No-op at chapter
        /// boundaries — ReaderView detects those via the pagination
        /// engine and triggers a chapter swap instead.
        ///
        /// WHEN isDoubleSided IS TRUE (iPad landscape + Page Curl):
        /// UIPageViewController requires `setViewControllers` to be
        /// called with an array of exactly two view controllers
        /// representing both sides of the spread. Passing a single
        /// VC in that mode produces no curl animation and appears to
        /// do nothing — which was the root cause of "tap changes
        /// page but doesn't curl" in spread mode.
        func turnPage(direction: UIPageViewController.NavigationDirection) {
            guard let pvc = pageViewController,
                  let currentVCs = pvc.viewControllers,
                  let currentLeft = currentVCs.first as? ChapterPageVC
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
                let newLeft = makePageVC(pageIndex: nextLeftIndex)
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
            guard let vc = viewController as? ChapterPageVC,
                  vc.pageIndex > 1 else { return nil }
            return makePageVC(pageIndex: vc.pageIndex - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? ChapterPageVC,
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
                    as? ChapterPageVC
            else { return }
            currentPage = current.pageIndex
            onPageChanged(currentPage)
        }

        // MARK: Message handler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let parsed = PaginationMessage(from: message.body) else { return }

            // Locate the sender VC. Every live page VC posts its own
            // messages — the coordinator decides which ones to forward
            // to the view model and which ones to react to locally.
            let senderVC = senderChapterPageVC(for: message.webView)
            let isCurrent: Bool = {
                guard let current = pageViewController?.viewControllers?
                                       .first as? ChapterPageVC else { return false }
                return senderVC === current
            }()

            switch parsed {
            case .pagination(let total, let current, _):
                #if DEBUG
                NSLog("[Codex] pagination msg total=\(total) current=\(current) senderPageIndex=\(senderVC?.pageIndex ?? -1) isCurrent=\(isCurrent)")
                #endif
                // EVERY page VC needs to lock to its assigned page once
                // its JS has measured. Without this snap the VC's web
                // view sits on page 1 (the JS default) even when the
                // VC represents page 5 — which made chapter-internal
                // paging appear to never advance (identical pages
                // curling endlessly). Snapping here is safe and
                // idempotent.
                senderVC?.snapToAssignedPage()
                // Forward the totals up once — the view model's engine
                // records totalPages for the data source and metadata
                // strip. Using the current VC's report is sufficient;
                // neighbours will report the same totals.
                if isCurrent {
                    onPaginationMessage(parsed)
                }
                // Cross-chapter spread filler: if the VC that just
                // reported its measurements is the right-hand page of
                // an iPad-landscape Page Curl spread AND its assigned
                // pageIndex doesn't exist in this chapter (chapter
                // ends short of the spread's right slot), replace it
                // with the next chapter's page 1 so the open-book
                // spread shows continuous reading flow instead of a
                // duplicate filler page.
                swapInCrossChapterRightPageIfNeeded(
                    senderVC: senderVC,
                    reportedTotal: total
                )

            case .pageChanged, .scrollProgress:
                // Only the currently-visible VC's page-level events
                // should move the view model's state. Neighbour VCs'
                // events during swipe preview would otherwise confuse
                // "where am I?"
                if isCurrent {
                    onPaginationMessage(parsed)
                }
            }
        }

        /// Match the sending web view back to the ChapterPageVC that
        /// owns it. The registry holds weak refs to every VC the
        /// coordinator has created — any VC UIKit is still keeping
        /// alive is still in this set.
        private func senderChapterPageVC(
            for webView: WKWebView?
        ) -> ChapterPageVC? {
            guard let webView else { return nil }
            for vc in liveVCs.allObjects where vc.webView === webView {
                return vc
            }
            return nil
        }

        /// When the right-hand page of an iPad-landscape Page Curl
        /// spread reports a total that's smaller than its assigned
        /// page index, the VC was created for a page that doesn't
        /// exist in this chapter (the most common case is a chapter
        /// that's exactly one page long — its right-hand slot in the
        /// spread has nowhere to land). Replace that VC with the next
        /// chapter's page 1 so the spread shows continuous reading
        /// flow instead of either a duplicate of the left page or a
        /// blank filler.
        ///
        /// Implementation notes:
        ///  - Only fires when we have a `nextChapterURL`. When this
        ///    chapter is the last in the spine, the right slot stays
        ///    blank (PaginationJS hides the body when it can't snap to
        ///    its assigned page) — that's the right behaviour at the
        ///    end of the book.
        ///  - We only replace when senderVC IS the right-hand VC.
        ///    Both VCs in the spread may report totals; we don't want
        ///    to react to the LEFT-hand VC's report.
        ///  - Animation off: this happens during initial layout or
        ///    right after a chapter load, well before the user sees a
        ///    transition. Animating would produce a visible flicker.
        private func swapInCrossChapterRightPageIfNeeded(
            senderVC: ChapterPageVC?,
            reportedTotal: Int
        ) {
            guard let pvc = pageViewController,
                  pvc.isDoubleSided,
                  let vcs = pvc.viewControllers,
                  vcs.count == 2,
                  let leftVC = vcs.first as? ChapterPageVC,
                  let rightVC = vcs.last as? ChapterPageVC,
                  rightVC === senderVC,
                  rightVC.pageIndex > reportedTotal,
                  let nextURL = nextChapterURL,
                  let readAccess = readAccessURL
            else { return }

            // Don't loop: if the right-hand VC is ALREADY a cross-
            // chapter page (its chapter URL differs from this
            // coordinator's current chapter URL), we've already
            // swapped — leave it alone.
            if rightVC.chapterURL != chapterURL {
                return
            }

            let crossChapterVC = makePageVC(
                chapterURL: nextURL,
                readAccessURL: readAccess,
                pageIndex: 1
            )
            pvc.setViewControllers(
                [leftVC, crossChapterVC],
                direction: .forward,
                animated: false,
                completion: nil
            )
        }
    }
}
