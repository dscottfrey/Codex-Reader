//
//  AnnotationReviewView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The annotation review screen — the list of all highlights, notes,
//  and bookmarks for a single book in reading order, with filter tabs
//  and an export button. Defined in Module 6 (Annotation System) §4.
//
//  WHY ITS OWN FILE:
//  It's a self-contained screen that's reachable from two places (the
//  reader's options panel and the library context menu). Keeping it
//  standalone means the same view backs both entry points.
//

import SwiftUI
import SwiftData

/// The annotation review screen — list of all annotations for a book
/// with filter tabs and an Export entry point.
struct AnnotationReviewView: View {

    let book: Book

    /// Called when the user taps an annotation row — the host should
    /// dismiss the panel and navigate the reader to that position.
    let onJumpToAnnotation: (Annotation) -> Void

    @Environment(\.modelContext) private var context
    @State private var filter: ReviewFilter = .all
    @State private var exportPickerVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterTabs
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                List {
                    ForEach(filtered, id: \.id) { annotation in
                        row(for: annotation)
                            .contentShape(Rectangle())
                            .onTapGesture { onJumpToAnnotation(annotation) }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Annotations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { exportPickerVisible = true }
                }
            }
            .confirmationDialog(
                "Export Annotations",
                isPresented: $exportPickerVisible,
                titleVisibility: .visible
            ) {
                ForEach(AnnotationExportFormat.allCases) { format in
                    Button(format.displayName) { performExport(format) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Pieces

    /// Filter tab strip. Mirrors directive §4: All / Highlights / Notes
    /// / Bookmarks.
    private var filterTabs: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ReviewFilter.allCases) { f in
                Text(f.displayName).tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    private func row(for a: Annotation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(for: a)
            VStack(alignment: .leading, spacing: 4) {
                Text(textPreview(for: a))
                    .font(.subheadline)
                    .lineLimit(3)
                if let note = a.noteText, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("Chapter • \(a.chapterHref)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let color = a.highlightColor {
                colorSwatch(color)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func icon(for a: Annotation) -> some View {
        switch a.type {
        case .highlight: Image(systemName: "highlighter")
        case .note:      Image(systemName: "note.text")
        case .bookmark:  Image(systemName: "bookmark")
        }
    }

    private func colorSwatch(_ color: HighlightColor) -> some View {
        Circle()
            .fill(swiftUIColor(for: color))
            .frame(width: 14, height: 14)
    }

    private func swiftUIColor(for color: HighlightColor) -> Color {
        switch color {
        case .yellow: return .yellow.opacity(0.6)
        case .green:  return .green.opacity(0.6)
        case .blue:   return .blue.opacity(0.5)
        case .pink:   return .pink.opacity(0.5)
        case .orange: return .orange.opacity(0.6)
        }
    }

    /// Preview text for the row. Until the parser can hand back the
    /// real chapter text by offset, we render the offset range as the
    /// preview — same compromise as in AnnotationExporter.
    private func textPreview(for a: Annotation) -> String {
        switch a.type {
        case .bookmark:  return a.bookmarkLabel ?? "Bookmark"
        case .highlight, .note: return "[\(a.startOffset)–\(a.endOffset)]"
        }
    }

    // MARK: - Data

    private var filtered: [Annotation] {
        let store = AnnotationStore(context: context)
        let all = store.allAnnotations(forBookID: book.id)
        switch filter {
        case .all:        return all
        case .highlights: return all.filter { $0.type == .highlight }
        case .notes:      return all.filter { $0.type == .note }
        case .bookmarks:  return all.filter { $0.type == .bookmark }
        }
    }

    private func delete(at offsets: IndexSet) {
        let store = AnnotationStore(context: context)
        for index in offsets {
            store.softDelete(filtered[index])
        }
    }

    private func performExport(_ format: AnnotationExportFormat) {
        let store = AnnotationStore(context: context)
        let exporter = AnnotationExporter(
            book: book,
            annotations: store.allAnnotations(forBookID: book.id)
        )
        _ = exporter.writeToTempFile(as: format)
        // TODO: present EpubShareSheet with the resulting URL — left
        // here as the next-step UI wiring once we have a host that can
        // present a sheet over the review screen without conflicting
        // with the existing one.
    }
}

/// Filter tabs for the review list per directive §4.
private enum ReviewFilter: String, CaseIterable, Identifiable {
    case all
    case highlights
    case notes
    case bookmarks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:        return "All"
        case .highlights: return "Highlights"
        case .notes:      return "Notes"
        case .bookmarks:  return "Bookmarks"
        }
    }
}
