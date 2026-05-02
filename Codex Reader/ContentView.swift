//
//  ContentView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The app's root view. Decides whether to show the Library or the
//  Reader, based on whether a book is currently open.
//
//  WHY IT'S SO THIN:
//  All of the real UI lives in `LibraryView` and `ReaderView`. ContentView
//  is just the dispatcher — that keeps it tiny and easy to evolve when
//  later iterations add things like a "first launch onboarding" branch
//  (Overall Directive §11) or a deep-link arrival.
//
//  WHY THERE'S A DEBUG AUTO-OPEN BLOCK BELOW:
//  During the current development cycle Scott wants a bundled sample
//  epub to be preloaded into the reader on every cold launch, so
//  iterating on the Rendering Engine doesn't require a tap through
//  the Library each time. The block is gated by `#if DEBUG` and fires
//  exactly once per launch — closing the reader returns to the library
//  normally, so Library / Ingestion UI work isn't blocked. Which sample
//  reopens is whichever was last opened (slug stored in UserDefaults
//  by `DevSampleBook.rememberLastOpened`), so switching to a different
//  sample in the Library Menu sticks across cold launches. Remove this
//  block (and the `hasAutoOpenedSample` flag) when Scott says the dev
//  cycle is done with it.
//
//  WHY WE FORCE pageTurnStyle = .curl IN DEBUG:
//  Scott is iterating on the iPad-landscape Page Curl renderer in the
//  simulator. The shipped default in `ReaderSettings` is now `.curl`
//  (also a dev-cycle setting), but a simulator that has run an older
//  build will already have a stored ReaderSettingsRecord with `.slide`
//  baked in — and changing the static default doesn't migrate existing
//  records. So in DEBUG we also realign the stored setting to `.curl`
//  on every cold launch. This is a dev override, not user-facing
//  behaviour: in Release the user's stored choice always wins. Drop
//  this when the dev cycle is done with it.
//

import SwiftUI
import SwiftData

/// Top-level dispatcher: Library when no book is open, Reader when one is.
struct ContentView: View {

    /// The currently-open book. Pushing a Book into this @State opens the
    /// reader; clearing it returns to the library. ReaderView calls back
    /// through a closure to clear it.
    @State private var openBook: Book?

    #if DEBUG
    /// One-shot guard for the dev-cycle auto-open of the sample epub.
    /// Stays true after the first auto-open so dismissing the reader
    /// returns to the library instead of immediately re-opening the
    /// sample. Reset on every cold launch (it's just @State).
    @State private var hasAutoOpenedSample = false
    #endif

    /// The user's global ReaderSettings, used to construct the
    /// ReaderViewModel when a book opens.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let book = openBook {
                ReaderView(
                    viewModel: ReaderViewModel(
                        book: book,
                        globalSettings: ReaderSettingsRecord.current(in: modelContext).settings
                    ),
                    onClose: { openBook = nil }
                )
            } else {
                LibraryView(onOpenBook: { book in
                    openBook = book
                })
            }
        }
        #if DEBUG
        .task {
            // Dev-cycle convenience: materialise all three sample epubs
            // into SwiftData so they all appear in the library, then
            // drop straight into whichever one was last opened (or the
            // first sample on a fresh install). Compiled out of Release.
            guard !hasAutoOpenedSample, openBook == nil else { return }
            hasAutoOpenedSample = true
            forceDevPageTurnStyle()
            DevSampleBook.materialiseAll(in: modelContext)
            let sample = DevSampleBook.lastOpenedOrDefault
            if let book = DevSampleBook.materialise(sample, in: modelContext) {
                DevSampleBook.rememberLastOpened(sample)
                openBook = book
            }
        }
        #endif
    }

    #if DEBUG
    /// Realign the stored global ReaderSettings to use Page Curl, so an
    /// older simulator install that already has `.slide` saved gets
    /// flipped to `.curl` for the current dev cycle. No-op when the
    /// stored value already matches. Compiled out of Release builds.
    @MainActor
    private func forceDevPageTurnStyle() {
        let record = ReaderSettingsRecord.current(in: modelContext)
        guard record.settings.pageTurnStyle != .curl else { return }
        var updated = record.settings
        updated.pageTurnStyle = .curl
        record.settings = updated
        try? modelContext.save()
    }
    #endif
}
