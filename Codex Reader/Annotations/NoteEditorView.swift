//
//  NoteEditorView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The modal text editor shown when the user adds or edits a note on
//  a highlight. Defined in Module 6 (Annotation System) §2.2.
//
//  WHY ITS OWN FILE:
//  The note editor is a small focused screen but it has to support
//  Dynamic Type, the system keyboard avoidance, and screen readers
//  (directive §9). Keeping it standalone lets each of those
//  refinements happen here without touching the popover code.
//

import SwiftUI

/// Bottom-sheet note editor. Pre-fills with `initialText` when editing
/// an existing note; empty when creating a new one.
struct NoteEditorView: View {

    let initialText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onCancel = onCancel
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            // TextEditor does the right thing with Dynamic Type and
            // keyboard avoidance out of the box — no custom handling
            // required, per the §6.5 "work with Apple, not against it"
            // rule.
            TextEditor(text: $text)
                .padding()
                .navigationTitle(initialText.isEmpty ? "Add Note" : "Edit Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { onSave(text) }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
        }
    }
}
