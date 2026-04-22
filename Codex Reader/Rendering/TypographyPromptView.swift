//
//  TypographyPromptView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The first-open typography prompt — Publisher's Style / My Defaults /
//  Customize. Defined in Module 1 (Rendering Engine) §4.6.
//
//  WHAT'S HERE IN v1 SCAFFOLDING:
//  The choice UI (three buttons, "Skip for now") and the wiring back to
//  the Book record. The split-pane PREVIEW (publisher style on the left,
//  my defaults on the right, with linked scrolling) is a Phase 2
//  refinement — it requires two WKWebViews driven from the parsed
//  excerpt, which is blocked on the parser spike. For now the panel
//  shows a clean text-only explanation of each choice.
//

import SwiftUI

/// Result of the user's choice from the prompt — passed back to the
/// caller so it can persist the decision.
enum TypographyPromptChoice {
    case publisherDefault
    case userDefaults
    case customize     // open the in-reader settings panel in This Book mode
    case skip          // dismiss without persisting; will reappear next open
}

/// The first-open typography prompt overlay.
struct TypographyPromptView: View {

    let book: Book

    /// Called when the user makes a choice. The caller is responsible
    /// for actually applying it (setting `book.typographyMode`, opening
    /// the customise panel, etc.).
    let onChoice: (TypographyPromptChoice) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {

                Text("How would you like to read this book?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top, 8)

                Text("You can change this any time from Book Details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Three choice cards. Each is a minimal explanation. The
                // future preview pane will live above this.
                choiceCard(
                    title: "Publisher's Style",
                    body: "Use the fonts, sizes, and layout the publisher chose for this book.",
                    action: { commit(.publisherDefault) }
                )

                choiceCard(
                    title: "My Defaults",
                    body: "Apply your own font, size, and layout preferences to this book.",
                    action: { commit(.userDefaults) }
                )

                choiceCard(
                    title: "Customize…",
                    body: "Adjust this book's typography from the publisher's starting point.",
                    action: { onChoice(.customize) }
                )

                Spacer()

                Button("Skip for now", action: { onChoice(.skip) })
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .navigationTitle(book.title.isEmpty ? "Welcome" : book.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    /// Persist the simple two-mode choices (Publisher / Defaults) and
    /// notify the caller. The Customise path is handled differently —
    /// it transitions into the settings panel and only stores
    /// `.custom` once the user taps Done there.
    private func commit(_ choice: TypographyPromptChoice) {
        switch choice {
        case .publisherDefault:
            book.typographyMode = .publisherDefault
        case .userDefaults:
            book.typographyMode = .userDefaults
        case .customize, .skip:
            break
        }
        onChoice(choice)
    }

    private func choiceCard(title: String, body: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
