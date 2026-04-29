//
//  PaginationEngine.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Swift-side store for "how many pages is the current chapter and
//  which one am I on." Sibling file to PaginationJS.swift — PaginationJS
//  measures pages inside the WKWebView and posts them here; this engine
//  holds the latest values for the rest of the reader UI to observe.
//
//  WHY IT'S ITS OWN OBJECT:
//  The ReaderViewModel is already doing a lot (chapter loading, CSS,
//  errors, chrome state). Pagination has its own state machine — reset
//  on chapter change, updated by JS messages, read by tap-zone
//  handlers and the metadata strip. Keeping it separate means each
//  file stays under the §6.3 budget and the pagination logic can be
//  tested independently of the view model.
//
//  THREE KINDS OF "WHERE AM I":
//  - Paginated mode: `currentPage` / `totalPages` (1-based).
//  - Scroll mode: `scrollProgress` (0.0–1.0 inside the chapter).
//  - Book-level progress comes from the spine index + chapter-local
//    progress; computed here so the metadata strip can show it.
//

import Foundation
import SwiftUI

/// Holds the current pagination state for the open chapter, and
/// exposes read-only computed progress for the UI.
@MainActor
@Observable
final class PaginationEngine {

    // MARK: - State reported by PaginationJS

    /// True while the current chapter is being rendered in a paginated
    /// mode (Slide, and eventually Curl). False when in Scroll mode —
    /// callers read this to decide whether to show "Page X of Y" or a
    /// percentage bar.
    private(set) var paginated: Bool = true

    /// 1-based current page inside the current chapter. Always 1 while
    /// the chapter is still loading or while in scroll mode.
    private(set) var currentPage: Int = 1

    /// Total pages in the current chapter. 1 while loading; 1 in scroll
    /// mode.
    private(set) var totalPages: Int = 1

    /// 0.0–1.0 vertical scroll progress inside the chapter. Only
    /// meaningful in scroll mode; stays 0 in paginated mode.
    private(set) var scrollProgress: Double = 0.0

    /// How many pages are on screen at once. 1 everywhere except the
    /// iBooks-style "open book" spread (iPad landscape + Page Curl),
    /// where both sides of a two-page layout are visible simultaneously.
    /// The `atLast/FirstPageOfChapter` checks use this so a forward
    /// tap on the right page of a spread correctly crosses the
    /// chapter boundary instead of silently no-op'ing.
    private(set) var visiblePages: Int = 1

    // MARK: - Spine context

    /// The spine index of the chapter currently loaded, for book-level
    /// progress. -1 until the first chapter lands.
    private(set) var currentSpineIndex: Int = -1

    /// Cached spine length so book-level progress can be computed
    /// without re-reading the parsed epub every frame.
    private(set) var spineCount: Int = 0

    /// Cache of measured `totalPages` per spine index. Populated as
    /// the user visits each chapter — the entry for a chapter lands
    /// the first time its JS reports pagination. Used by the
    /// cumulative book-page count and the "pages left in book"
    /// estimate.
    ///
    /// APPROXIMATE BY DESIGN. Chapters the user hasn't visited yet
    /// contribute 0 to known totals; the average-based estimate
    /// extrapolates from visited chapters to the rest of the spine.
    /// For a strictly-linear read the cache fills as reading
    /// progresses and the numbers tighten naturally. For a reader
    /// who jumps around (TOC, scrubber) the running totals will
    /// drift upward as new chapters are measured. This matches the
    /// approximation philosophy already used by `bookProgress`.
    private var chapterPageCounts: [Int: Int] = [:]

    // MARK: - Mutation (called by the JS bridge)

    /// Called when a new chapter starts loading. Clears per-chapter
    /// state so stale values don't leak into the UI between chapters.
    func willLoadChapter(spineIndex: Int, spineCount: Int) {
        self.currentSpineIndex = spineIndex
        self.spineCount = spineCount
        self.currentPage = 1
        self.totalPages = 1
        self.scrollProgress = 0.0
    }

    /// JS has finished measuring — capture the new totals. Called once
    /// at chapter render and again on resize (live font change, rotate).
    func reportPagination(total: Int, current: Int, paginated: Bool) {
        self.paginated = paginated
        self.totalPages = max(1, total)
        self.currentPage = max(1, min(current, self.totalPages))
        // Record this chapter's page count so the cumulative
        // book-page metrics below have something to add up.
        if currentSpineIndex >= 0 {
            chapterPageCounts[currentSpineIndex] = self.totalPages
        }
    }

    /// JS confirms a page turn — keep our mirror in sync.
    func reportPageChanged(to page: Int) {
        self.currentPage = max(1, min(page, totalPages))
    }

    /// Scroll-mode progress tick.
    func reportScrollProgress(_ progress: Double) {
        self.scrollProgress = max(0, min(1, progress))
    }

    /// The coordinator reports how many pages the UIPageViewController
    /// is currently showing — 1 for single-page, 2 for the iPad
    /// landscape "open book" spread. Clamped to [1, 2].
    func reportVisiblePages(_ count: Int) {
        self.visiblePages = max(1, min(2, count))
    }

    // MARK: - Derived — what the UI asks for

    /// Progress inside the current chapter as a 0.0–1.0 value. Works
    /// for both paginated (page/total) and scroll mode.
    var chapterProgress: Double {
        if paginated {
            guard totalPages > 1 else { return 0 }
            return Double(currentPage - 1) / Double(totalPages - 1)
        }
        return scrollProgress
    }

    /// Progress through the whole book (0.0–1.0). Combines spine index
    /// with progress-inside-chapter. Approximate — assumes chapters are
    /// roughly equal length. Good enough for the metadata strip and the
    /// page-stack-edges depth indicator (§2.9). For a precise % we'd
    /// need per-chapter word counts, which is a future enhancement.
    var bookProgress: Double {
        guard spineCount > 0, currentSpineIndex >= 0 else { return 0 }
        let perChapter = 1.0 / Double(spineCount)
        let base = Double(currentSpineIndex) * perChapter
        return min(1.0, base + chapterProgress * perChapter)
    }

    /// Pages remaining in this chapter. The "most practically useful
    /// metric" per directive §4.4 — how much is left of my current
    /// reading session before chapter break.
    var pagesRemainingInChapter: Int {
        paginated ? max(0, totalPages - currentPage) : 0
    }

    /// Cumulative page count in the entire book, up to and INCLUDING
    /// the current page. Built from cached chapter page counts:
    /// sum of every previously-visited chapter's totalPages, plus
    /// the current page within the current chapter.
    ///
    /// For a linear read this is exact. For a reader who jumps
    /// around it under-counts at first and grows toward the true
    /// number as chapters get visited.
    var cumulativePageInBook: Int {
        guard paginated, currentSpineIndex >= 0 else { return currentPage }
        var pagesBeforeCurrent = 0
        for i in 0..<currentSpineIndex {
            pagesBeforeCurrent += chapterPageCounts[i] ?? 0
        }
        return pagesBeforeCurrent + currentPage
    }

    /// Estimated total pages in the entire book. Average of visited
    /// chapters' page counts, scaled to the full spine length.
    /// Same approximation philosophy as `bookProgress`. When no
    /// chapters have been measured yet (impossible after the first
    /// pagination report, but defensive), falls back to whatever the
    /// running cumulative count is so the "left" metric below
    /// returns 0 instead of a negative number.
    var estimatedTotalPagesInBook: Int {
        guard paginated, !chapterPageCounts.isEmpty, spineCount > 0
        else { return cumulativePageInBook }
        let totalMeasured = chapterPageCounts.values.reduce(0, +)
        let avgPerChapter = Double(totalMeasured) / Double(chapterPageCounts.count)
        return Int((avgPerChapter * Double(spineCount)).rounded())
    }

    /// Estimated pages remaining in the entire book. Approximate —
    /// see `estimatedTotalPagesInBook`.
    var pagesRemainingInBook: Int {
        paginated ? max(0, estimatedTotalPagesInBook - cumulativePageInBook) : 0
    }

    /// Short user-facing string, e.g. "Page 47 of 523". Both numbers
    /// are book-level: cumulative position in the whole book / the
    /// estimated total page count for the whole book. The estimate
    /// is approximate (see `estimatedTotalPagesInBook`) — Scott
    /// signed off on the approximation as good enough for a reading
    /// progress indicator. Scroll mode returns a percentage instead
    /// since there are no pages.
    var shortPositionLabel: String {
        if paginated {
            return "Page \(cumulativePageInBook) of \(estimatedTotalPagesInBook)"
        }
        return "\(Int((scrollProgress * 100).rounded()))% through chapter"
    }

    // MARK: - Intent helpers

    /// True when the reader is on the last page of the current chapter —
    /// i.e. a "next page" tap should cross the chapter boundary. In a
    /// two-page spread the right page is `currentPage + 1`, so the
    /// boundary is reached one page earlier than in single-page mode.
    var atLastPageOfChapter: Bool {
        guard paginated else { return scrollProgress >= 0.999 }
        return currentPage + (visiblePages - 1) >= totalPages
    }

    /// True when the reader is on the first page — a "previous page"
    /// tap should cross back into the previous chapter.
    var atFirstPageOfChapter: Bool {
        paginated ? currentPage <= 1 : scrollProgress <= 0.001
    }
}
