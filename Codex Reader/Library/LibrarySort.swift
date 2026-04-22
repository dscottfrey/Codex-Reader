//
//  LibrarySort.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The sort options for the library — Title / Author / Date Added /
//  Last Read / Reading Progress, each with a forward and reverse
//  variant. Defined in Module 3 (Library Manager) §8.2.
//
//  WHY ITS OWN FILE:
//  Same reasoning as LibraryFilter: the sort is shared between the
//  bookshelf, the list view, and the search results, and the rules
//  belong in one place so they cannot drift apart.
//

import Foundation

/// One sort option for the library.
enum LibrarySort: String, CaseIterable, Identifiable {

    case titleAZ
    case titleZA
    case authorAZ
    case authorZA
    case dateAddedNewest
    case dateAddedOldest
    case lastReadMostRecent
    case progressUnreadFirst
    case progressFinishedFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .titleAZ:               return "Title A–Z"
        case .titleZA:               return "Title Z–A"
        case .authorAZ:              return "Author A–Z"
        case .authorZA:              return "Author Z–A"
        case .dateAddedNewest:       return "Date Added (newest)"
        case .dateAddedOldest:       return "Date Added (oldest)"
        case .lastReadMostRecent:    return "Last Read"
        case .progressUnreadFirst:   return "Progress (unread first)"
        case .progressFinishedFirst: return "Progress (finished first)"
        }
    }

    /// Apply this sort order to a list of books and return the sorted
    /// result. Stable in ties so book order doesn't shuffle on every
    /// re-render.
    func apply(to books: [Book]) -> [Book] {
        switch self {
        case .titleAZ:
            return books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .authorAZ:
            return books.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .authorZA:
            return books.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedDescending }
        case .dateAddedNewest:
            return books.sorted { $0.dateAdded > $1.dateAdded }
        case .dateAddedOldest:
            return books.sorted { $0.dateAdded < $1.dateAdded }
        case .lastReadMostRecent:
            return books.sorted {
                ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast)
            }
        case .progressUnreadFirst:
            return books.sorted { $0.readingProgress < $1.readingProgress }
        case .progressFinishedFirst:
            return books.sorted { $0.readingProgress > $1.readingProgress }
        }
    }
}
