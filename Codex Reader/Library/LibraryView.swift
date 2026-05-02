//
//  LibraryView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Library tab — bookshelf or list view of the user's books, plus
//  the filter tabs and the toggle between the two views. Defined in
//  Module 3 (Library Manager) §2 / §3 / §8.
//
//  WHY ITS OWN FILE:
//  This is the dispatcher between the two main library views, and the
//  host of the filter / sort UI. Keeping each individual view in its
//  own file (BookshelfView, BookListView, EmptyLibraryView) means
//  LibraryView can be small enough to read in one screen.
//

import SwiftUI
import SwiftData

/// Top-level Library view — dispatches to the bookshelf, the list, or
/// the empty state, with the persistent toggle in the navigation bar.
struct LibraryView: View {

    /// Open the given book in the reader.
    let onOpenBook: (Book) -> Void

    /// Whether the bookshelf or list view is showing. Persists across
    /// launches per directive §3 — TODO: hook to UserDefaults once a
    /// Settings store exists.
    @State private var viewMode: ViewMode = .bookshelf

    /// Currently-selected filter tab.
    @State private var filter: LibraryFilter = .all

    @Query private var books: [Book]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    #if DEBUG
                    ToolbarItem(placement: .topBarLeading) {
                        devSampleToolbarButton
                    }
                    #endif
                    ToolbarItem(placement: .topBarTrailing) {
                        viewModeToggle
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !books.isEmpty {
                        filterTabs.padding(.bottom, 4)
                    }
                }
        }
    }

    #if DEBUG
    /// Need ModelContext to materialise samples into SwiftData when a
    /// menu item is picked — see `DevSampleBook.materialise(_:in:)`.
    @Environment(\.modelContext) private var devModelContext

    /// Dev-only nav-bar Menu that lists the bundled sample epubs and
    /// opens whichever the user picks, bypassing the library. Compiled
    /// out of Release.
    private var devSampleToolbarButton: some View {
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
            Image(systemName: "hammer")
        }
        .accessibilityLabel("Open sample epub (debug)")
    }
    #endif

    // MARK: - Pieces

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            EmptyLibraryView(onOpenBook: onOpenBook)
        } else {
            switch viewMode {
            case .bookshelf: BookshelfView(onOpenBook: onOpenBook)
            case .list:      BookListView(onOpenBook: onOpenBook)
            }
        }
    }

    /// The persistent two-way toggle in the trailing nav bar position.
    private var viewModeToggle: some View {
        Button {
            viewMode = (viewMode == .bookshelf) ? .list : .bookshelf
        } label: {
            Image(systemName: viewMode == .bookshelf ? "list.bullet" : "books.vertical")
        }
        .accessibilityLabel(viewMode == .bookshelf ? "Switch to list" : "Switch to bookshelf")
    }

    /// The horizontal filter tabs row above the library content.
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryFilter.allCases) { f in
                    Button(f.displayName) { filter = f }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(filter == f ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// The two ways to view the library — the bookshelf, or the
/// information-dense list.
private enum ViewMode {
    case bookshelf
    case list
}
