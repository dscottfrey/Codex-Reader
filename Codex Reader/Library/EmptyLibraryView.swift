//
//  EmptyLibraryView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The empty-state screen for the Library, shown when the user has no
//  books yet. Defined in Module 3 (Library Manager) §12 and tied to the
//  first-launch sequence in Overall Directive §11.
//
//  WHY ITS OWN FILE:
//  This is the first screen a brand-new user sees. The directive is
//  explicit that it must be calm and instructive. Keeping it standalone
//  means design tweaks happen here, not buried inside LibraryView.
//
//  WHY THERE'S A DEV-ONLY MENU BELOW:
//  A `#if DEBUG`-gated "Open Sample (dev)" Menu lets us open one of
//  the bundled sample epubs directly from an empty library, bypassing
//  the ingestion pipeline. It is compiled out of Release builds
//  entirely. See DevSampleBook.swift for the mechanism.
//

import SwiftUI
import SwiftData

/// Empty library screen — calm, no celebration, two clear actions.
struct EmptyLibraryView: View {

    /// Opens a Book in the reader. Passed down from LibraryView so the
    /// dev-only sample button can land in the reader the same way a
    /// normal library row does.
    let onOpenBook: (Book) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Your library is empty")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add books from your Calibre server, iCloud Drive, AirDrop, or the Files app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Browse Sources") {
                    // TODO: Navigate to Sources tab (Module 3)
                }
                .buttonStyle(.bordered)

                Button("Add a Book") {
                    // TODO: Open document picker (Module 2 ingestion entry)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

            #if DEBUG
            devSampleButton
                .padding(.top, 24)
            #endif
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    /// Need ModelContext to materialise samples into SwiftData when a
    /// menu item is picked — see `DevSampleBook.materialise(_:in:)`.
    @Environment(\.modelContext) private var devModelContext

    /// Dev-only shortcut — Menu of the bundled sample epubs that loads
    /// the picked one directly into the reader, bypassing ingestion.
    /// Compiled out of Release builds.
    private var devSampleButton: some View {
        VStack(spacing: 4) {
            Menu {
                ForEach(DevSampleBook.all) { sample in
                    Button(sample.title) {
                        if let book = DevSampleBook.materialise(sample, in: devModelContext) {
                            DevSampleBook.rememberLastOpened(sample)
                            onOpenBook(book)
                        }
                    }
                }
            } label: {
                Label("Open Sample (dev)", systemImage: "hammer")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Text("Debug builds only — choose a sample epub to load.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    #endif
}
