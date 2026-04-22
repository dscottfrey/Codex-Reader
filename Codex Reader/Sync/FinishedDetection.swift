//
//  FinishedDetection.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The "Finished?" decision logic — when to surface the shelf prompt
//  and what its three toggles do. Defined in Module 4 (Sync Engine)
//  §13.
//
//  WHY ITS OWN FILE:
//  The bookshelf cell decides whether to show the Finished? button per
//  book. The completion panel decides what to do when the user
//  confirms. Both share the same rules; centralising them here means
//  the rules don't drift between callers.
//

import Foundation

enum FinishedDetection {

    /// Default progress threshold (90%) per directive §13.2 — books
    /// below this never get the Finished? prompt. Configurable in
    /// Advanced Settings.
    static let defaultProgressThreshold: Double = 0.90

    /// Default idle period (7 days) per §13.2 — the book has to have
    /// been quiet for a week before we ask.
    static let defaultIdlePeriod: TimeInterval = 60 * 60 * 24 * 7

    /// Decide whether the Finished? button should appear on the
    /// shelf for `book`. All three §13.2 conditions must be true.
    static func shouldShowPrompt(
        for book: Book,
        progressThreshold: Double = defaultProgressThreshold,
        idlePeriod: TimeInterval = defaultIdlePeriod,
        now: Date = Date()
    ) -> Bool {

        // Already marked finished — never prompt again.
        if book.isFinished { return false }

        // Not far enough through.
        if book.readingProgress < progressThreshold { return false }

        // Not idle long enough.
        guard let lastRead = book.lastReadDate else { return false }
        let idle = now.timeIntervalSince(lastRead)
        return idle >= idlePeriod
    }

    /// The three independent toggles surfaced in the Finished? panel
    /// per §13.3. Carrying them as a struct so the call site is one
    /// `apply(_:)` rather than three Bools and a conditional.
    struct Choices {
        var rememberEndPoint: Bool = false
        var removeFromShelf: Bool = false
        var remindNextTimeIDownloadThis: Bool = false
    }

    /// Apply the user's choices to the book record. Returns whether
    /// the caller should also delete the file (Choice 2 — "Remove from
    /// shelf"). The caller is responsible for the actual file
    /// deletion since it touches iCloud Drive, which the directive
    /// keeps separate from data mutations.
    @discardableResult
    static func apply(_ choices: Choices, to book: Book, now: Date = Date()) -> Bool {

        // Mark the book finished regardless of which toggles are on —
        // confirming the panel is the user saying "I'm done with this."
        book.isFinished = true

        if choices.rememberEndPoint {
            // §13.4: store the current position as the custom end point.
            book.customEndPoint = book.readingProgress
        }

        if choices.remindNextTimeIDownloadThis {
            // §13.5: persist the flag with a timestamp so the
            // re-ingestion prompt can read it later.
            book.didNotFinish = true
            book.didNotFinishDate = now
        }

        return choices.removeFromShelf
    }
}
