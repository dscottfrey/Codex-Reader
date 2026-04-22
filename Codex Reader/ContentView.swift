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

import SwiftUI
import SwiftData

/// Top-level dispatcher: Library when no book is open, Reader when one is.
struct ContentView: View {

    /// The currently-open book. Pushing a Book into this @State opens the
    /// reader; clearing it returns to the library. ReaderView calls back
    /// through a closure to clear it.
    @State private var openBook: Book?

    /// The user's global ReaderSettings, used to construct the
    /// ReaderViewModel when a book opens.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let book = openBook {
                ReaderView(viewModel: ReaderViewModel(
                    book: book,
                    globalSettings: ReaderSettingsRecord.current(in: modelContext).settings
                ))
            } else {
                LibraryView(onOpenBook: { book in
                    openBook = book
                })
            }
        }
    }
}
