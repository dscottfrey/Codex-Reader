//
//  SidecarFile.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The on-disk shape of a `.codex` sidecar — the parallel record of a
//  book's reading state that lives next to its epub in iCloud Drive.
//  Defined in Module 4 (Sync Engine) §12.
//
//  WHY IT'S A PLAIN Codable STRUCT:
//  Sidecars are written as JSON to a file path next to the epub. They
//  must be readable by any future version of Codex (and theoretically by
//  a script if the user ever needs to recover one by hand). A plain
//  Codable struct produces clean, human-readable JSON.
//
//  WHY ITS OWN FILE:
//  Encoding/decoding/writing happens in SidecarWriter (next file). This
//  file just declares the schema so the writer and any future reader
//  share one definition.
//

import Foundation

/// On-disk shape of a `.codex` sidecar file. One per book, written
/// next to the epub in `iCloud Drive/Codex/Library/`.
///
/// The format intentionally leaves room for new fields — older versions
/// of Codex should ignore unknown keys (Foundation's JSONDecoder does
/// this naturally), and newer versions should write missing optional
/// fields as nil.
struct SidecarFile: Codable {

    /// Schema version. Bump on backwards-incompatible changes.
    let formatVersion: Int

    /// When this sidecar was last written. Used for last-write-wins
    /// reconciliation against CloudKit (§12.1).
    let lastWritten: Date

    let bookID: UUID
    let title: String
    let author: String

    /// Reading position when the sidecar was written.
    let chapterHref: String?
    let scrollOffset: Double
    let readingProgress: Double
    let isFinished: Bool

    /// Optional custom end point — the user's "this book ends here"
    /// override (Sync Engine §13.4).
    let customEndPoint: Double?

    /// "Did not finish" flag from §13.5.
    let didNotFinish: Bool
    let didNotFinishDate: Date?

    /// All annotations (highlights, notes, bookmarks) for this book at
    /// the moment of writing. The Annotation System owns this type;
    /// SidecarFile uses a parallel local struct to avoid coupling
    /// SidecarFile to the SwiftData @Model. The conversion happens in
    /// SidecarWriter.
    let annotations: [SidecarAnnotation]

    /// Build the canonical sidecar filename from a book's epub path:
    /// "Author - Title.epub" → "Author - Title.codex".
    static func sidecarFilename(forEpubFilename epubFilename: String) -> String {
        let stem = (epubFilename as NSString).deletingPathExtension
        return stem + ".codex"
    }
}

/// JSON-friendly mirror of an Annotation, kept here so SidecarFile is
/// portable and doesn't drag the SwiftData model definition along
/// when the JSON is read by an external tool.
struct SidecarAnnotation: Codable {
    let id: UUID
    let type: String           // "highlight" | "note" | "bookmark"
    let chapterHref: String
    let startOffset: Int
    let endOffset: Int
    let highlightColor: String?
    let noteText: String?
    let bookmarkLabel: String?
    let createdAt: Date
}
