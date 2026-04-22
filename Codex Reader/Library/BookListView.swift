//
//  BookListView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The information-dense list view of the library — an alternative to
//  the bookshelf for readers who prefer text. Defined in Module 3
//  (Library Manager) §5.
//
//  WHY ITS OWN FILE:
//  The list and the bookshelf are two distinct views of the same data.
//  The directive's mental model treats them as peers — the user toggles
//  between them via a navigation-bar button. Keeping them in separate
//  files means they can have unrelated layout changes without merge
//  conflicts.
//

import SwiftUI
import SwiftData

/// The information-dense list of books.
struct BookListView: View {

    let onOpenBook: (Book) -> Void

    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]

    var body: some View {
        List {
            ForEach(books, id: \.id) { book in
                row(for: book)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenBook(book) }
            }
        }
        .listStyle(.plain)
    }

    /// One list row: small cover, title, author, secondary metadata
    /// (series, progress, last-read date), and a state indicator on the
    /// trailing edge for any non-normal iCloud state.
    private func row(for book: Book) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(book: book, width: 44, height: 66)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title.isEmpty ? "Untitled" : book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(book.author.isEmpty ? "Unknown Author" : book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let series = book.series {
                    Text(series + (book.seriesNumber.map { String(format: ", %g", $0) } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(progressText(for: book))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            stateIndicator(for: book.iCloudFileState)
        }
        .padding(.vertical, 4)
    }

    /// Plain-text progress label — "47%" or "Finished".
    private func progressText(for book: Book) -> String {
        if book.isFinished { return "Finished" }
        let pct = Int((book.readingProgress * 100).rounded())
        return pct == 0 ? "Unread" : "\(pct)%"
    }

    /// The tiny SF Symbol shown for non-normal iCloud states. Defined in
    /// directive §6.5 — same icons across the bookshelf and the list.
    @ViewBuilder
    private func stateIndicator(for state: ICloudFileState) -> some View {
        switch state {
        case .synced, .localOnly:
            EmptyView()
        case .uploading:
            Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)
        case .uploadError:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .cloudOnly:
            Image(systemName: "icloud").foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
        case .downloadError:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .missing:
            Image(systemName: "link.badge.minus").foregroundStyle(.tertiary)
        }
    }
}
