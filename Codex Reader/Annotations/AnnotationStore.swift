//
//  AnnotationStore.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The CRUD entry point for annotations — create / fetch / soft-delete
//  highlights, notes, and bookmarks. Defined in Module 6 (Annotation
//  System) §5.
//
//  WHY ITS OWN FILE:
//  Multiple callers create annotations: the rendering engine's text-
//  selection callout, the bookmark ribbon tap handler, the
//  Highlight Back to Previous flow. Centralising the store means the
//  rules (soft-delete instead of hard delete; writing modifiedAt;
//  preserving the chapterHref) live in one place.
//
//  WHY SOFT DELETE:
//  See Annotation.swift's header — soft-delete lets a deletion sync
//  through CloudKit as a value change rather than a missing record.
//

import Foundation
import SwiftData

@MainActor
struct AnnotationStore {

    let context: ModelContext

    // MARK: - Highlights

    /// Create a highlight at a character range in a chapter.
    @discardableResult
    func addHighlight(
        bookID: UUID,
        chapterHref: String,
        startOffset: Int,
        endOffset: Int,
        color: HighlightColor = .yellow
    ) -> Annotation {
        let a = Annotation(
            bookID: bookID,
            type: .highlight,
            chapterHref: chapterHref,
            startOffset: startOffset,
            endOffset: endOffset,
            highlightColor: color
        )
        context.insert(a)
        try? context.save()
        return a
    }

    // MARK: - Notes

    /// Create a highlight+note. Per directive (§10) note-only
    /// (without highlight) is deferred to v1.1.
    @discardableResult
    func addNote(
        bookID: UUID,
        chapterHref: String,
        startOffset: Int,
        endOffset: Int,
        color: HighlightColor = .yellow,
        text: String
    ) -> Annotation {
        let a = Annotation(
            bookID: bookID,
            type: .note,
            chapterHref: chapterHref,
            startOffset: startOffset,
            endOffset: endOffset,
            highlightColor: color,
            noteText: text
        )
        context.insert(a)
        try? context.save()
        return a
    }

    // MARK: - Bookmarks

    /// Create a bookmark at the user's current reading position. Bookmarks
    /// store start==end offsets per the §5 schema.
    @discardableResult
    func addBookmark(
        bookID: UUID,
        chapterHref: String,
        offset: Int,
        label: String? = nil
    ) -> Annotation {
        let a = Annotation(
            bookID: bookID,
            type: .bookmark,
            chapterHref: chapterHref,
            startOffset: offset,
            endOffset: offset,
            bookmarkLabel: label
        )
        context.insert(a)
        try? context.save()
        return a
    }

    // MARK: - Update / delete

    /// Update an annotation's fields and bump `modifiedAt`. Pass through
    /// to context.save so the change syncs immediately.
    func update(_ annotation: Annotation, mutate: (Annotation) -> Void) {
        mutate(annotation)
        annotation.modifiedAt = Date()
        try? context.save()
    }

    /// Soft-delete: stamp `deletedAt` so CloudKit propagates the
    /// removal. The hard-purge path (after the 30-day window) is the
    /// Sync Engine's job.
    func softDelete(_ annotation: Annotation) {
        annotation.deletedAt = Date()
        annotation.modifiedAt = Date()
        try? context.save()
    }

    // MARK: - Queries

    /// Fetch all live (non-deleted) annotations for one chapter,
    /// ordered by start offset. Used by the AnnotationInjector at
    /// chapter-load time.
    func annotations(forBookID bookID: UUID, chapterHref: String) -> [Annotation] {
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate {
                $0.bookID == bookID &&
                $0.chapterHref == chapterHref &&
                $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.startOffset)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch all live annotations for a book in reading order — used
    /// by the review screen and the export.
    func allAnnotations(forBookID bookID: UUID) -> [Annotation] {
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookID == bookID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.chapterHref), SortDescriptor(\.startOffset)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Lookup a bookmark at the exact (chapterHref, offset) — used by
    /// the bookmark ribbon to decide if it should be drawn solid or
    /// outlined.
    func bookmark(forBookID bookID: UUID, chapterHref: String, offset: Int) -> Annotation? {
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate {
                $0.bookID == bookID &&
                $0.chapterHref == chapterHref &&
                $0.startOffset == offset &&
                $0.typeRaw == "bookmark" &&
                $0.deletedAt == nil
            }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
