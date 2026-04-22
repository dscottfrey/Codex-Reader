//
//  ShelfRowView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  One named row on the bookshelf — the shelf label, the wooden surface
//  beneath the books, and a horizontally scrolling row of BookCellView
//  instances. Defined in Module 3 (Library Manager) §4.2 and §4.5.
//
//  WHY ITS OWN FILE:
//  The bookshelf is composed of many of these. Keeping the row in its
//  own file means the parent BookshelfView is just a vertical stack of
//  ShelfRowViews — easy to read, easy to add a new shelf type later.
//
//  THE WOODEN SURFACE:
//  v1 ships the §4.5 "flat / modern-skeuomorphic" option — a wood-toned
//  colour with a subtle highlight along the top edge. No texture image.
//  This matches Occam's Razor; the textured option can be added later
//  by replacing the background view with an Image.
//

import SwiftUI

/// A single labeled bookshelf row: the title, the wood surface, and the
/// books arranged horizontally on it.
struct ShelfRowView: View {

    let title: String
    let books: [Book]
    let onOpenBook: (Book) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if !books.isEmpty {
                    Button("See all", action: onShowAll)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)

            shelfSurface
                .overlay(alignment: .center) {
                    bookRow
                }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Pieces

    /// The wooden plank visual — a warm gradient stack with a thin
    /// highlight at the top to suggest a horizontal surface catching
    /// light from above.
    private var shelfSurface: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#8B6F3D"),
                    Color(hex: "#6E5530")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                Spacer()
            }
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }

    /// The horizontal scroll of book cells. We use a ScrollView + LazyHStack
    /// so cells off-screen are not built — important for a 3,000-book
    /// shelf (directive performance §16).
    private var bookRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(books, id: \.id) { book in
                    BookCellView(book: book) { onOpenBook(book) }
                }
            }
            .padding(.horizontal, 24)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }
}
