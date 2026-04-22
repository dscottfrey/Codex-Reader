//
//  LibraryView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Placeholder of the library's top-level screen for Module 1's compile
//  pass. The full Bookshelf / List / Sources implementation lives in
//  Module 3 (Library Manager) and will replace most of this file.
//
//  WHY THIS PLACEHOLDER EXISTS:
//  Without something to render at the root, Module 1's code can't be
//  exercised end-to-end. This view shows whatever Books are in SwiftData
//  as a plain list, plus the canonical empty state from §12 of the
//  Library Manager directive. Module 3 will subsume it.
//

import SwiftUI
import SwiftData

/// Stand-in library screen — list of books with an empty state.
/// Replaced by `BookshelfView` etc. when Module 3 is built.
struct LibraryView: View {

    /// Open the given book in the reader.
    let onOpenBook: (Book) -> Void

    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    EmptyLibraryView()
                } else {
                    List(books, id: \.id) { book in
                        Button {
                            onOpenBook(book)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(book.title.isEmpty ? "Untitled" : book.title)
                                    .font(.headline)
                                Text(book.author.isEmpty ? "Unknown Author" : book.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}
