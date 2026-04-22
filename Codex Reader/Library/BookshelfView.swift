//
//  BookshelfView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The skeuomorphic bookshelf — a vertical stack of named shelves, each
//  a horizontally scrolling row of books with the cover-to-spine
//  transition. Defined in Module 3 (Library Manager) §4.
//
//  WHY THE STRUCTURE LOOKS THE WAY IT DOES:
//  Per §4.2 the shelf order is: Now Reading, Up Next, user collections,
//  Everything Else. We build them in that order. Empty shelves are
//  skipped — so a brand-new library that doesn't have any "Now Reading"
//  books shows just "Everything Else" and looks calm rather than empty
//  with chrome.
//

import SwiftUI
import SwiftData

/// The bookshelf screen — vertical stack of shelves.
struct BookshelfView: View {

    let onOpenBook: (Book) -> Void

    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {

                // Shelf 1 — Now Reading. Books with progress > 0 and
                // not finished, ordered by most recently opened.
                let nowReading = allBooks.filter { $0.readingProgress > 0 && !$0.isFinished }
                if !nowReading.isEmpty {
                    ShelfRowView(
                        title: "Now Reading",
                        books: nowReading,
                        onOpenBook: onOpenBook,
                        onShowAll: { /* TODO: open CoverFlow browser §4.6 */ }
                    )
                }

                // Shelf 2 — Up Next. v1: this is empty until series logic
                // and the "Read Next" tag exist. We still render it when
                // there are entries so the structure is in place.
                let upNext = upNextBooks(from: allBooks, currentReading: nowReading)
                if !upNext.isEmpty {
                    ShelfRowView(
                        title: "Up Next",
                        books: upNext,
                        onOpenBook: onOpenBook,
                        onShowAll: { /* TODO: open CoverFlow */ }
                    )
                }

                // Last shelf — Everything Else. Books not on any of the
                // above shelves and not in any user collection.
                let everythingElse = allBooks.filter {
                    !nowReading.contains($0) && !upNext.contains($0)
                }
                if !everythingElse.isEmpty {
                    ShelfRowView(
                        title: "Everything Else",
                        books: everythingElse,
                        onOpenBook: onOpenBook,
                        onShowAll: { /* TODO: open CoverFlow */ }
                    )
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// Compute the Up Next shelf. v1 implements the manual "Read Next"
    /// tag path only — the auto "next in series" path needs the series
    /// metadata field on Book to be populated, which the parser stub
    /// doesn't do yet (TODO once parser is real).
    private func upNextBooks(from all: [Book], currentReading: [Book]) -> [Book] {
        // TODO: Pull books tagged "Read Next" via Collection lookup.
        // Stub: nothing in v1 scaffolding.
        return []
    }
}
