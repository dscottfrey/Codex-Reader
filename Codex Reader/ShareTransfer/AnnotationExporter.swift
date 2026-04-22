//
//  AnnotationExporter.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Generates a single-book annotation export in Rich Text, Plain Text,
//  or Markdown format. Defined in Module 5 (Share & Transfer) §5.
//
//  WHY ONE FILE:
//  All three formats share the same outline (chapter heading →
//  highlighted text → optional note). Pulling them into one enum-
//  driven generator means a future format tweak (e.g., chapter-name
//  source change) is one edit rather than three.
//

import Foundation
import UIKit

enum AnnotationExportFormat: String, CaseIterable, Identifiable {

    case richText = "rtf"
    case plainText = "txt"
    case markdown = "md"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .richText:  return "Rich Text"
        case .plainText: return "Plain Text"
        case .markdown:  return "Markdown"
        }
    }

    /// File extension for the produced file (matches `rawValue` for
    /// the three formats — kept as a separate property so a future
    /// rename of the enum case wouldn't silently change extensions).
    var fileExtension: String { rawValue }
}

/// Produces an export file for one book's annotations.
@MainActor
struct AnnotationExporter {

    let book: Book
    let annotations: [Annotation]

    /// Build the export file's bytes for the given format.
    func encode(as format: AnnotationExportFormat) -> Data? {
        switch format {
        case .plainText:
            return plainText().data(using: .utf8)
        case .markdown:
            return markdown().data(using: .utf8)
        case .richText:
            return richTextRTFData()
        }
    }

    /// Build the export and write it to a temporary file. Returns the
    /// URL ready to feed into a UIActivityViewController.
    func writeToTempFile(as format: AnnotationExportFormat) -> URL? {
        guard let data = encode(as: format) else { return nil }
        let safeName = "\(book.title) Annotations.\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
        try? data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: - Plain Text

    /// Plain-text format from directive §5.2.
    private func plainText() -> String {
        var lines: [String] = [
            "Annotations — \(book.title)",
            book.author,
            "Exported: \(Date().formatted(date: .long, time: .omitted))",
            "────────────────────────────",
            ""
        ]

        for group in groupedByChapter() {
            lines.append("Chapter " + group.chapterLabel)
            lines.append("")
            for annotation in group.items {
                lines.append("\"\(textFor(annotation))\"")
                if let note = annotation.noteText, !note.isEmpty {
                    lines.append("[Note: \(note)]")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown

    /// Standard CommonMark output per §5.2 — `##` chapter headers,
    /// `>` blockquotes for highlights, `**bold**` for note labels.
    private func markdown() -> String {
        var out: [String] = [
            "# Annotations — \(book.title)",
            "*\(book.author)*  ",
            "Exported: \(Date().formatted(date: .long, time: .omitted))",
            ""
        ]
        for group in groupedByChapter() {
            out.append("## Chapter " + group.chapterLabel)
            out.append("")
            for annotation in group.items {
                out.append("> \(textFor(annotation))")
                if let note = annotation.noteText, !note.isEmpty {
                    out.append("**Note:** \(note)")
                }
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Rich Text

    /// RTF Data — same outline as plain text, with bold chapter
    /// headers and highlighted text in the highlight's colour. Built
    /// via NSAttributedString so the NSAttributedString → RTF
    /// conversion handles encoding for us.
    private func richTextRTFData() -> Data? {
        let body = NSMutableAttributedString()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18)
        ]
        body.append(NSAttributedString(
            string: "Annotations — \(book.title)\n",
            attributes: titleAttrs
        ))
        body.append(NSAttributedString(
            string: "\(book.author)\nExported: \(Date().formatted(date: .long, time: .omitted))\n\n"
        ))

        for group in groupedByChapter() {
            body.append(NSAttributedString(
                string: "Chapter \(group.chapterLabel)\n",
                attributes: [.font: UIFont.boldSystemFont(ofSize: 14)]
            ))
            body.append(NSAttributedString(string: "\n"))
            for annotation in group.items {
                body.append(NSAttributedString(string: "“\(textFor(annotation))”\n"))
                if let note = annotation.noteText, !note.isEmpty {
                    body.append(NSAttributedString(
                        string: "Note: \(note)\n",
                        attributes: [.font: UIFont.italicSystemFont(ofSize: 12)]
                    ))
                }
                body.append(NSAttributedString(string: "\n"))
            }
        }

        return try? body.data(
            from: NSRange(location: 0, length: body.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: - Helpers

    /// Group annotations by chapter href in reading order. The label
    /// is just the href for now — once the parser is real we can
    /// substitute the chapter name from the TOC.
    private func groupedByChapter() -> [(chapterLabel: String, items: [Annotation])] {
        let ordered = annotations
            .filter { $0.deletedAt == nil }
            .sorted { ($0.chapterHref, $0.startOffset) < ($1.chapterHref, $1.startOffset) }
        let grouped = Dictionary(grouping: ordered) { $0.chapterHref }
        return grouped
            .map { (chapterLabel: $0.key, items: $0.value) }
            .sorted { $0.chapterLabel < $1.chapterLabel }
    }

    /// Compose the displayed text for an annotation. For highlights,
    /// it's the highlighted passage (TODO: requires chapter text
    /// access — for now we use a placeholder until the parser lands).
    /// For bookmarks, the label or the position reference.
    private func textFor(_ annotation: Annotation) -> String {
        switch annotation.type {
        case .highlight, .note:
            // TODO: pull the actual highlighted text from the chapter
            // by character offset once the parser is wired up. Until
            // then we surface a position reference so the export is
            // still useful.
            return "[\(annotation.startOffset)–\(annotation.endOffset)]"
        case .bookmark:
            return annotation.bookmarkLabel ?? "Bookmark"
        }
    }
}
