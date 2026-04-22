//
//  BookDetailView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Book Detail sheet — book metadata, file & sync status, reading
//  history, and an Open Book button. Defined in Module 3 (Library
//  Manager) §11.
//
//  WHY ITS OWN FILE:
//  The detail sheet is reachable from many places: the bookshelf
//  context menu, the list view swipe action, the Reader's options
//  panel. Presenting it from one shared view means the user always
//  sees the same screen regardless of how they got there.
//
//  WHAT'S IN AND WHAT'S OUT FOR v1 SCAFFOLDING:
//  The three sections (Info / File & Sync / Reading History) are laid
//  out as a SwiftUI Form. The actual edit forms (replace cover, edit
//  title, etc.) are stubbed to keep file size reasonable; the read-only
//  display works.
//

import SwiftUI

/// The Book Detail sheet — read-mostly view of all of a book's
/// metadata and state, plus the Open Book entry point.
struct BookDetailView: View {

    let book: Book
    let onOpenBook: (Book) -> Void

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                fileSyncSection
                readingHistorySection

                Section {
                    Button {
                        onOpenBook(book)
                    } label: {
                        Label("Open Book", systemImage: "book.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .navigationTitle(book.title.isEmpty ? "Untitled" : book.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section("Info") {
            CoverView(book: book, width: 90, height: 135)
                .frame(maxWidth: .infinity, alignment: .center)

            row("Title", book.title)
            row("Author", book.author)
            if let series = book.series { row("Series", series) }
            row("Language", book.language)
            if let publisher = book.publisher { row("Publisher", publisher) }
            row("Epub Version", book.epubVersion)
            if let words = book.wordCountEstimate {
                row("Word Count", words.formatted())
            }
            row("Date Added", book.dateAdded.formatted(date: .abbreviated, time: .omitted))
            if let last = book.lastReadDate {
                row("Last Read", last.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    // MARK: - File & sync

    private var fileSyncSection: some View {
        Section("File & Sync") {
            row("State", iCloudStateText(book.iCloudFileState))
            row("Storage", book.storageLocation == .iCloudDrive ? "iCloud Drive" : "Local Only")
            row("File Size", ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
            // TODO: Replace File… and Force Re-upload buttons —
            // delegate to the Ingestion Engine when the UI flow is built.
        }
    }

    // MARK: - Reading history

    private var readingHistorySection: some View {
        Section("Reading History") {
            row("Progress", "\(Int((book.readingProgress * 100).rounded()))%")
            if let endPoint = book.customEndPoint {
                row("Custom End Point", "\(Int((endPoint * 100).rounded()))%")
            }
            if book.didNotFinish, let date = book.didNotFinishDate {
                row("Did Not Finish", date.formatted(date: .abbreviated, time: .omitted))
            }
            // TODO: Reset Progress button.
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func iCloudStateText(_ state: ICloudFileState) -> String {
        switch state {
        case .synced:        return "Stored in iCloud"
        case .uploading:     return "Uploading…"
        case .uploadError:   return "Upload stuck"
        case .cloudOnly:     return "Not downloaded"
        case .downloading:   return "Downloading…"
        case .downloadError: return "Download stuck"
        case .localOnly:     return "Local only"
        case .missing:       return "File missing"
        }
    }
}
