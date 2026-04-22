//
//  CoverView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Renders one book's cover image — either loaded from the cached file
//  on disk (CoverExtractor put it there) or, as a last-resort fallback,
//  a tinted SF Symbol so the layout never has a missing image hole.
//
//  WHY ITS OWN FILE:
//  Cover rendering is used by the bookshelf cells, the list rows, the
//  Book Detail view, and the OPDS results. Centralising it here means
//  one cache-aware loader serves them all and any future image-loading
//  optimisation (e.g., NSCache integration per directive §16) is one
//  edit in one file.
//

import SwiftUI

/// Display a book cover at the requested size. Loads from the cached
/// file on disk if available, otherwise shows a placeholder.
struct CoverView: View {

    let book: Book
    var width: CGFloat = 90
    var height: CGFloat = 135

    /// Controls whether to apply a soft drop-shadow under the cover —
    /// off by default. The bookshelf cells turn it on for the
    /// face-out centre book to give the "resting on a shelf" feel.
    var dropShadow: Bool = false

    var body: some View {
        coverImage
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(
                color: dropShadow ? Color.black.opacity(0.3) : .clear,
                radius: dropShadow ? 6 : 0,
                x: 0, y: dropShadow ? 3 : 0
            )
    }

    @ViewBuilder
    private var coverImage: some View {
        if let path = book.coverCachePath,
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Visible-but-quiet placeholder — the SF Symbol "book.closed"
            // tinted on the same hue family CoverExtractor uses.
            ZStack {
                Color(hue: 0.6, saturation: 0.2, brightness: 0.45)
                Image(systemName: "book.closed")
                    .resizable()
                    .scaledToFit()
                    .padding(width * 0.25)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
