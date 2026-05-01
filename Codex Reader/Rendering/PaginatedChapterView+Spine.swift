//
//  PaginatedChapterView+Spine.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The `UIPageViewController` "spine location" delegate method, split
//  out of PaginatedChapterView.swift to keep that file under the §6.3
//  line budget. Directive §2.9 had the iBooks-style centre-spine
//  layout explicitly deferred, but Scott has brought it back in for
//  Page Curl: on iPad landscape you see two facing pages at once, just
//  like Apple Books.
//
//  HOW IT WORKS:
//  UIPageViewController calls `spineLocationFor:orientation:` whenever
//  it needs to decide whether to display one page or two. We return:
//    • `.min` (single page, spine notionally on the left) for iPhone,
//      iPad portrait, Slide, and Scroll. These surfaces never show a
//      spread.
//    • `.mid` (two pages, spine in the middle) only when all three
//      conditions hold: device is iPad, orientation is landscape, and
//      the transition style is `.pageCurl`. The directive is explicit
//      that Slide stays single-page.
//
//  WHEN WE SWITCH TO `.mid` we must pair the currently-visible VC
//  with a neighbour and set `isDoubleSided = true`. When switching
//  back to `.min` we reduce the spread to the single left page.
//
//  The coordinator also notifies the pagination engine via
//  `onVisiblePagesChanged` so the "are we at the last page?" check
//  knows the right page of the spread is `currentPage + 1`.
//

import UIKit

extension PaginatedChapterView.Coordinator {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
    ) -> UIPageViewController.SpineLocation {

        // Only Page Curl supports a two-page spread — Slide and
        // Scroll are always single-page.
        guard pageViewController.transitionStyle == .pageCurl else {
            return switchToSinglePage(pageViewController)
        }

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if isIPad && orientation.isLandscape {
            return switchToTwoPageSpread(pageViewController)
        } else {
            return switchToSinglePage(pageViewController)
        }
    }

    // MARK: - Single-page arrangement

    private func switchToSinglePage(
        _ pvc: UIPageViewController
    ) -> UIPageViewController.SpineLocation {
        // If we're currently in a spread, keep the LEFT page as the
        // visible single page — that matches what iBooks does on
        // rotate-to-portrait (the current user-visible left page
        // stays put; the right page disappears).
        if let visible = pvc.viewControllers,
           visible.count > 1,
           let leftPage = visible.first {
            pvc.setViewControllers(
                [leftPage],
                direction: .forward,
                animated: false,
                completion: nil
            )
        }
        pvc.isDoubleSided = false
        notifyVisiblePages(1)
        return .min
    }

    // MARK: - Two-page spread arrangement

    private func switchToTwoPageSpread(
        _ pvc: UIPageViewController
    ) -> UIPageViewController.SpineLocation {
        guard let currentVCs = pvc.viewControllers,
              let currentLeft = currentVCs.first as? PageImageVC
        else {
            // No current VC (shouldn't happen after init) — fall back.
            pvc.isDoubleSided = false
            notifyVisiblePages(1)
            return .min
        }

        // Already a two-page spread — nothing to reconfigure.
        if currentVCs.count == 2 {
            pvc.isDoubleSided = true
            notifyVisiblePages(2)
            return .mid
        }

        // Build the right-hand page for the current left page. If the
        // current page IS the last page, we still need a right page
        // to satisfy UIPageViewController's spread requirement — use
        // a blank placeholder so the spine renders correctly without
        // a phantom "page N+1" the reader can turn to.
        let rightIndex = currentLeft.pageIndex + 1
        let rightPage = makePageVC(pageIndex: rightIndex)

        pvc.setViewControllers(
            [currentLeft, rightPage],
            direction: .forward,
            animated: false,
            completion: nil
        )
        pvc.isDoubleSided = true
        notifyVisiblePages(2)
        return .mid
    }

    // MARK: - Helper

    /// Forward the current visible-page count up to the pagination
    /// engine so chapter-boundary checks stay correct.
    private func notifyVisiblePages(_ count: Int) {
        reportVisiblePagesChanged(count)
    }
}
