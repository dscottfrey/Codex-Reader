//
//  PageNavigator.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The decision function for "what does a tap on the left/right edge
//  actually DO?" It looks at the current pagination state and the
//  current spine position and returns one of four intents:
//
//    - turnWithinChapter(direction)  — JS handles the page shift.
//    - crossToNextChapter            — load the next spine item.
//    - crossToPrevChapter(atEnd:)    — load previous, jump to last page.
//    - atEndOfBook / atStartOfBook   — nothing to do.
//
//  WHY IT'S A PURE FUNCTION, NOT A STATEFUL CLASS:
//  It has no state of its own — it reads from the PaginationEngine and
//  the ParsedEpub, and returns the intent for the caller to execute.
//  Keeping it free of state makes it easy to reason about from the
//  view model and easy to test once we add unit tests.
//
//  WHY INTENT, NOT IMPERATIVE:
//  The navigator doesn't call into the view model or run JS directly.
//  It returns an intent; the view model decides whether to honour it
//  (e.g. a "next page at end of book" could trigger a "Finished?"
//  prompt instead of crossing a chapter). Cleanly separates decision
//  from action.
//

import Foundation

/// What a left/right tap should do.
enum PageIntent: Equatable {

    /// Within-chapter page turn — the JS function handles this.
    case turnWithinChapter(direction: TurnDirection)

    /// Cross forward into the next spine item, landing on page 1.
    case crossToNextChapter(href: String)

    /// Cross backward into the previous spine item; after that chapter
    /// measures its pagination the navigator should jump to its last
    /// page (so the reader lands naturally at the end of the prior
    /// chapter, not at the beginning).
    case crossToPrevChapter(href: String)

    /// The user has paged off the end of the last chapter. Callers
    /// typically leave the page where it is and may show a "You've
    /// reached the end" prompt.
    case atEndOfBook

    /// The user has paged off the start of the first chapter. Callers
    /// leave the page where it is.
    case atStartOfBook

    enum TurnDirection { case forward, backward }
}

enum PageNavigator {

    /// Compute the intent for a "next page" gesture.
    static func nextPageIntent(
        pagination: PaginationEngine,
        spine: [ParsedEpub.SpineItem],
        currentHref: String?
    ) -> PageIntent {
        if !pagination.atLastPageOfChapter {
            return .turnWithinChapter(direction: .forward)
        }
        guard let next = neighbourHref(
            from: currentHref,
            spine: spine,
            offset: +1
        ) else {
            return .atEndOfBook
        }
        return .crossToNextChapter(href: next)
    }

    /// Compute the intent for a "previous page" gesture.
    static func prevPageIntent(
        pagination: PaginationEngine,
        spine: [ParsedEpub.SpineItem],
        currentHref: String?
    ) -> PageIntent {
        if !pagination.atFirstPageOfChapter {
            return .turnWithinChapter(direction: .backward)
        }
        guard let prev = neighbourHref(
            from: currentHref,
            spine: spine,
            offset: -1
        ) else {
            return .atStartOfBook
        }
        return .crossToPrevChapter(href: prev)
    }

    /// Look up the index of a chapter in the spine by href. Returns
    /// nil if the chapter isn't in the linear flow — useful for
    /// "where am I?" queries from the pagination engine.
    static func spineIndex(
        of href: String?,
        in spine: [ParsedEpub.SpineItem]
    ) -> Int? {
        guard let href else { return nil }
        return spine.firstIndex(where: { $0.href == href })
    }

    // MARK: - Private helpers

    /// Walk the spine by `offset` (+1 / -1) from the current chapter.
    /// Skips non-linear items — those are supplementary content
    /// (footnotes, preview chapters) and shouldn't interrupt the main
    /// reading flow on a plain page-turn gesture.
    private static func neighbourHref(
        from currentHref: String?,
        spine: [ParsedEpub.SpineItem],
        offset: Int
    ) -> String? {
        guard let current = currentHref,
              let currentIdx = spine.firstIndex(where: { $0.href == current })
        else { return nil }

        var i = currentIdx + offset
        while i >= 0 && i < spine.count {
            if spine[i].linear { return spine[i].href }
            i += offset
        }
        return nil
    }
}
