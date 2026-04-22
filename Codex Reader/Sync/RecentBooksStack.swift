//
//  RecentBooksStack.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The 5-deep most-recently-active book stack used by Follow Me / Stay
//  Here logic and the quick-switch gesture. Defined in Module 4 (Sync
//  Engine) §7.1, §7.2, §7.4.
//
//  WHY ITS OWN FILE:
//  The stack is queried from many places: app-open behaviour decides
//  what to open, the reader's quick-switch panel reads it, every
//  position-update touches it. Centralising the read/write rules here
//  means there's one definition of "what does most-recent mean."
//
//  WHY MAX 5:
//  The directive (§7.1) caps it at 5. Older entries are evicted when a
//  new one bumps them out, keeping the CloudKit zone small.
//

import Foundation
import SwiftData
import UIKit

@MainActor
struct RecentBooksStack {

    /// Largest size we ever keep. Per directive §7.1.
    static let maxEntries = 5

    let context: ModelContext

    /// Record (or update) that the user just opened/closed `book` at
    /// the given position. Trims the stack to `maxEntries` afterwards.
    func record(book: Book, chapterHref: String, scrollOffset: Double) {
        let descriptor = FetchDescriptor<RecentBookEntry>()
        let allEntries = (try? context.fetch(descriptor)) ?? []

        // Find existing entry for this book, or create one.
        let entry: RecentBookEntry
        if let existing = allEntries.first(where: { $0.bookID == book.id }) {
            entry = existing
        } else {
            entry = RecentBookEntry(
                bookID: book.id,
                titleSnapshot: book.title,
                deviceName: UIDevice.current.name,
                chapterHref: chapterHref,
                scrollOffset: scrollOffset
            )
            context.insert(entry)
        }

        entry.titleSnapshot = book.title
        entry.deviceName = UIDevice.current.name
        entry.chapterHref = chapterHref
        entry.scrollOffset = scrollOffset
        entry.lastUpdated = Date()

        // Trim — keep the newest `maxEntries`, evict the rest.
        let refreshed = (try? context.fetch(descriptor)) ?? []
        let sorted = refreshed.sorted { $0.lastUpdated > $1.lastUpdated }
        for old in sorted.dropFirst(Self.maxEntries) {
            context.delete(old)
        }
        try? context.save()
    }

    /// The current stack contents, newest first.
    func current() -> [RecentBookEntry] {
        let descriptor = FetchDescriptor<RecentBookEntry>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Decide what to open at app launch given the user's Follow Me /
    /// Stay Here mode (§7.2). Returns the bookID to open, or nil if
    /// the stack is empty (the library is shown instead).
    ///
    /// - Parameters:
    ///   - mode: User's preference.
    ///   - timeAssistedThreshold: When `mode` is .followMe with a time
    ///     limit, entries older than this fall through to "Stay Here"
    ///     behaviour (§7.3).
    func bookToOpenAtLaunch(
        mode: FollowMeMode,
        timeAssistedThreshold: TimeInterval? = nil
    ) -> UUID? {

        let stack = current()
        guard let newest = stack.first else { return nil }

        switch mode {
        case .followMe:
            if let threshold = timeAssistedThreshold {
                let age = Date().timeIntervalSince(newest.lastUpdated)
                if age > threshold {
                    return stayHereBook(stack: stack)
                }
            }
            return newest.bookID

        case .stayHere:
            return stayHereBook(stack: stack)
        }
    }

    /// "Stay Here" semantics — return the most recent entry that was
    /// written by THIS device.
    private func stayHereBook(stack: [RecentBookEntry]) -> UUID? {
        let myDevice = UIDevice.current.name
        return stack.first(where: { $0.deviceName == myDevice })?.bookID
            ?? stack.first?.bookID  // sane fallback if no local entry exists
    }
}

/// The two top-level cross-device-resume behaviours from §7.2.
enum FollowMeMode: String, Codable {
    case followMe
    case stayHere
}
