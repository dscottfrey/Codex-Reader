//
//  SpineView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Renders one book in spine mode — the narrow vertical view used at
//  the edges of a bookshelf row. Defined in Module 3 (Library Manager)
//  §4.4.
//
//  WHY ITS OWN FILE:
//  The bookshelf face-swap (cover ↔ spine) is the central visual trick
//  of the Bookshelf view. The cell decides which face to show; this
//  file owns the spine face. Keeping cover and spine in separate files
//  means a future spine refinement (gradients, embossed text) can
//  happen without touching CoverView.
//

import SwiftUI

/// One book rendered as a vertical spine — coloured background,
/// rotated title and author text. The spine background colour and the
/// light/dark text choice are computed at ingestion time and cached on
/// the Book record so the render is cheap.
struct SpineView: View {

    let book: Book

    /// Width of the spine. Uniform across all books per directive §4.4
    /// — exposed as a parameter so the caller (the bookshelf row) can
    /// pass the configured Advanced Settings value.
    var width: CGFloat = 28

    /// Height of the spine — typically the same as the cover height in
    /// the same row, so spines and covers align vertically.
    var height: CGFloat = 135

    var body: some View {
        ZStack {
            backgroundColor
                .clipShape(RoundedRectangle(cornerRadius: 2))

            spineText
                .rotationEffect(.degrees(-90))
                // After the rotation the text is laid out across the
                // spine length; a fixed frame the OTHER way around
                // keeps SwiftUI from clipping it before rotation.
                .frame(width: height - 16, height: width)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Pieces

    /// Spine background colour. Pulled from the Book record (extracted
    /// from cover at ingestion time) or a neutral fallback when nothing
    /// has been cached yet.
    private var backgroundColor: Color {
        if let hex = book.spineColour {
            return Color(hex: hex)
        }
        return Color(hue: 0.6, saturation: 0.2, brightness: 0.45)
    }

    /// Title in semi-bold over a smaller author. Both ellipsised — title
    /// takes priority per directive §4.4.
    private var spineText: some View {
        let textColor = book.spineTextIsLight ? Color.white : Color.black
        return HStack(spacing: 8) {
            Text(book.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(book.author)
                .font(.caption2)
                .lineLimit(1)
                .opacity(0.85)
        }
        .foregroundStyle(textColor)
    }
}
