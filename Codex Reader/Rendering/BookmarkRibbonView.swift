//
//  BookmarkRibbonView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The persistent bookmark ribbon shown in a corner of every reading
//  page. Defined in Module 1 (Rendering Engine) §4.7 and Module 6
//  (Annotation System) §2.3.
//
//  WHY ITS OWN VIEW:
//  The ribbon has its own state (filled/outline), its own gesture
//  (tap to toggle, long-press to label), and is the canonical example of
//  the "small persistent on-page icon" pattern. Keeping it standalone
//  means we can use the same component anywhere a bookmark ribbon should
//  appear (reader, possibly the bookmarks list).
//

import SwiftUI

/// A ribbon-tab shape — the classic hardcover bookmark hanging from the
/// top of a page. Shown as outline when there's no bookmark, solid red
/// when one exists.
struct BookmarkRibbonView: View {

    // MARK: - Inputs

    /// Whether a bookmark exists at the current reading position.
    let isBookmarked: Bool

    /// Tap handler — toggle the bookmark. Per directive: instant, no
    /// confirmation, subtle haptic.
    let onTap: () -> Void

    /// Long-press handler — open the inline label editor.
    let onLongPress: () -> Void

    var body: some View {
        BookmarkShape()
            .fill(isBookmarked ? Color.red : Color.clear)
            .stroke(
                isBookmarked ? Color.red.opacity(0.8) : Color.secondary.opacity(0.6),
                lineWidth: 1.5
            )
            .frame(width: 22, height: 36)
            .contentShape(Rectangle())  // bigger tappable area than the V-cut shape
            .onTapGesture {
                triggerHaptic()
                onTap()
            }
            .onLongPressGesture {
                onLongPress()
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Add bookmark")
            .accessibilityAddTraits(.isButton)
    }

    /// A subtle confirmation tap — per directive §4.7, "a subtle haptic
    /// confirms" the immediate state change.
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

/// The ribbon outline — a tall rectangle with a V-notch cut from the
/// bottom edge. Drawn as a Path so it scales cleanly to any size.
private struct BookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // V-notch — meets in the middle of the bottom edge.
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
