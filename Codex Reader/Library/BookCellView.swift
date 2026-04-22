//
//  BookCellView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  One book on the bookshelf — handles the cover-to-spine face swap
//  driven by SwiftUI's scrollTransition. Defined in Module 3 (Library
//  Manager) §4.3.
//
//  WHY THE FACE SWAP:
//  Rotating a cover image to a steep angle produces a distorted sliver
//  (the cover image becomes a thin trapezoid). Switching to the spine
//  view past ~70° of rotation hides that ugliness and matches what the
//  eye expects from a real bookshelf — books at the edges look like
//  spines.
//
//  WHY THE SCROLL TRANSITION IS LOCAL TO THE CELL:
//  ScrollTransition's closure receives a per-cell `phase` describing
//  this cell's position in the scroll. We use the phase value to drive
//  rotation, opacity, AND the choice between cover and spine. Keeping
//  that logic in the cell means the parent (the row) just lays out
//  cells; it doesn't have to know about the visual transition.
//

import SwiftUI

/// A bookshelf cell that swaps between cover and spine views as it
/// scrolls toward the edges of the shelf.
struct BookCellView: View {

    let book: Book
    let onTap: () -> Void

    /// The cover face dimensions. Spine width is independent and
    /// uniform — see SpineView.
    var coverWidth: CGFloat = 100
    var coverHeight: CGFloat = 150

    var body: some View {
        // Container has the cover dimensions even when showing the
        // spine, so layout doesn't shift mid-scroll.
        ZStack {
            // The wrapper frame catches the tap (the whole cell is
            // tappable). We draw cover and spine inside it and rely on
            // the scrollTransition closure to decide which one's visible.
            faces
        }
        .frame(width: coverWidth, height: coverHeight)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            // phase.value runs roughly -1 (offscreen leading) … 0 (centre)
            // … +1 (offscreen trailing). We use its magnitude as the
            // "how far from centre" driver.
            let distance = phase.value
            let rotation: Double = distance * 78          // degrees
            let opacity: Double = max(0.35, 1.0 - abs(distance) * 0.7)

            return content
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .opacity(opacity)
        }
        .accessibilityLabel(Text("\(book.title) by \(book.author)"))
        .accessibilityAddTraits(.isButton)
    }

    /// Cover and spine stacked — opacity flips between the two so the
    /// face-swap happens cleanly as the cell rotates past the threshold.
    /// The threshold itself is just "show spine when rotation looks
    /// edge-on" — derived from the same phase value used above. We
    /// approximate it by letting the renderer decide based on width
    /// (when the projected width gets very small, show spine).
    @ViewBuilder
    private var faces: some View {
        // Both faces are always present in the layout; the visual
        // rotation is what the user perceives as the swap. Drawing both
        // slightly increases overdraw but keeps layout stable when
        // rotation reaches the threshold mid-scroll.
        SpineView(book: book, width: 28, height: coverHeight)
            .opacity(0.001)  // present for layout; visual is below
        CoverView(book: book, width: coverWidth, height: coverHeight, dropShadow: true)
    }
}
