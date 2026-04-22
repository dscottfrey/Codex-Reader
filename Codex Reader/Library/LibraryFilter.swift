//
//  LibraryFilter.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The filter tabs at the top of the library — All, Reading, Unread,
//  Finished, Unavailable. Defined in Module 3 (Library Manager) §8.1.
//
//  WHY ITS OWN FILE:
//  The filter is a tiny enum but it's used by both the Bookshelf and
//  List views, by the search results pane, and by the smart-collection
//  Collection records. Putting the rule (which Books match a filter) in
//  one place means there is one definition of "Reading" — progress > 0
//  and not finished — across the whole app.
//

import Foundation

/// The filter tab currently selected at the top of the library.
enum LibraryFilter: String, CaseIterable, Identifiable {

    case all
    case reading
    case unread
    case finished
    case unavailable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:         return "All"
        case .reading:     return "Reading"
        case .unread:      return "Unread"
        case .finished:    return "Finished"
        case .unavailable: return "Unavailable"
        }
    }

    /// True iff `book` matches this filter.
    ///
    /// `.all` includes every book except ghost records (missing files).
    /// `.unavailable` is the inverse — ghost records only.
    func matches(_ book: Book) -> Bool {
        let isGhost = (book.iCloudFileState == .missing)
        switch self {
        case .all:
            return !isGhost
        case .reading:
            return !isGhost && book.readingProgress > 0 && !book.isFinished
        case .unread:
            return !isGhost && book.readingProgress == 0
        case .finished:
            return !isGhost && book.isFinished
        case .unavailable:
            return isGhost
        }
    }
}
