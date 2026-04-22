//
//  Annotation.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The SwiftData record for a single annotation — highlight, note, or
//  bookmark. Schema defined in Module 6 (Annotation System) §5.
//
//  WHY IT'S HERE IN /Models RATHER THAN /Annotations:
//  Multiple modules need to reference Annotation: the sidecar writer
//  in /Sync, the export engine in /ShareTransfer, the highlight
//  injection in /Annotations. Living in /Models alongside Book
//  reflects its cross-module role and matches where Book sits.
//
//  WHY THE SOFT DELETE FIELD:
//  CloudKit sync needs the deletion of an annotation on one device to
//  propagate to the others. A row that's silently removed from the
//  local store can't tell CloudKit "this was deleted" — it just
//  disappears. Setting `deletedAt` lets the deletion sync as a value
//  change. After a propagation window (Sync Engine §6 specifies 30
//  days) records can be hard-purged.
//

import Foundation
import SwiftData

@Model
final class Annotation {

    @Attribute(.unique) var id: UUID = UUID()

    /// The Book this annotation belongs to. Stored as a UUID instead
    /// of a SwiftData relationship for the same reasons we did this on
    /// Collection.bookIDs — see comments in Collection.swift.
    var bookID: UUID = UUID()

    /// Which kind of annotation. Stored as the rawValue so SwiftData +
    /// CloudKit can sync it as a plain string.
    var typeRaw: String = AnnotationType.highlight.rawValue
    var type: AnnotationType {
        get { AnnotationType(rawValue: typeRaw) ?? .highlight }
        set { typeRaw = newValue.rawValue }
    }

    /// Spine href of the chapter this annotation lives in.
    var chapterHref: String = ""

    /// Character offset of the annotation's start within the chapter's
    /// rendered text. For bookmarks, equals `endOffset`.
    var startOffset: Int = 0

    /// Character offset of the annotation's end. For bookmarks,
    /// equals `startOffset`.
    var endOffset: Int = 0

    /// Highlight colour, when this is a highlight or note-with-highlight.
    /// Stored as rawValue (string) for the same SwiftData/CloudKit
    /// reasons as `typeRaw`.
    var highlightColorRaw: String?
    var highlightColor: HighlightColor? {
        get { highlightColorRaw.flatMap { HighlightColor(rawValue: $0) } }
        set { highlightColorRaw = newValue?.rawValue }
    }

    /// Free-text note attached to a highlight, or the body of a
    /// stand-alone note (note-only annotations are deferred to v1.1
    /// per directive §10).
    var noteText: String?

    /// Optional label for a bookmark, set via the long-press inline
    /// editor on the ribbon.
    var bookmarkLabel: String?

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Soft-delete marker — see file header.
    var deletedAt: Date?

    init(bookID: UUID = UUID(),
         type: AnnotationType = .highlight,
         chapterHref: String = "",
         startOffset: Int = 0,
         endOffset: Int = 0,
         highlightColor: HighlightColor? = nil,
         noteText: String? = nil,
         bookmarkLabel: String? = nil) {
        self.bookID = bookID
        self.typeRaw = type.rawValue
        self.chapterHref = chapterHref
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.highlightColorRaw = highlightColor?.rawValue
        self.noteText = noteText
        self.bookmarkLabel = bookmarkLabel
    }
}

/// The three annotation kinds. Named so the rawValue matches the
/// string values expected by the sidecar JSON and CloudKit schema.
enum AnnotationType: String, Codable, CaseIterable {
    case highlight
    case note
    case bookmark
}

/// The five highlight colour swatches available to the user.
enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, blue, pink, orange

    var id: String { rawValue }
}
