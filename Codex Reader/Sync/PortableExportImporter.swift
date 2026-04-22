//
//  PortableExportImporter.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Parses a `Codex-backup-*.json` file back into the SwiftData store —
//  the import side of the §11.4 round trip.
//
//  WHY ITS OWN FILE:
//  Export and import touch different code paths (write vs. read,
//  serialise vs. resolve-or-create), and the import is non-trivial: it
//  has to choose between merging onto existing records and replacing
//  them outright. Pulling import out keeps PortableExport.swift to the
//  shape of the file, while this file owns the merge rules.
//

import Foundation
import SwiftData

/// Strategies the user can choose when importing a backup. Names match
/// the buttons shown in the import sheet (§11.4).
enum ImportStrategy {

    /// Add or update — books already present are updated only if the
    /// imported `lastOpenedDate` is more recent. Annotations are
    /// merged (no duplicates by ID).
    case merge

    /// Wipe the existing SwiftData records and replace with the
    /// import. Epub files in iCloud Drive are not touched. Requires
    /// a confirmation step at the UI layer.
    case replace
}

/// Reads a portable export and applies it to the store per the chosen
/// strategy.
@MainActor
struct PortableExportImporter {

    let context: ModelContext

    /// Apply an import. Throws if the data is unreadable or doesn't
    /// look like a Codex export.
    func apply(_ data: Data, strategy: ImportStrategy) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(PortableExport.self, from: data)

        if strategy == .replace {
            wipeExistingData()
        }

        // Reader settings — always overwrite, regardless of strategy.
        // The settings file is one record so there's no merge possible.
        let settingsRecord = ReaderSettingsRecord.current(in: context)
        settingsRecord.settings = export.readerSettings

        // Books and their annotations.
        for exportedBook in export.books {
            mergeBook(exportedBook, strategy: strategy)
        }

        // Collections.
        for exportedCollection in export.collections {
            mergeCollection(exportedCollection, strategy: strategy)
        }

        try? context.save()
    }

    // MARK: - Private merges

    /// Wipe Books, Annotations, Collections from the store. Used by
    /// the `.replace` strategy.
    private func wipeExistingData() {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        for b in books { context.delete(b) }
        let annotations = (try? context.fetch(FetchDescriptor<Annotation>())) ?? []
        for a in annotations { context.delete(a) }
        let collections = (try? context.fetch(FetchDescriptor<Collection>())) ?? []
        for c in collections { context.delete(c) }
    }

    /// Merge one book into the store. For `.replace` we always insert
    /// (the wipe already cleared the slate). For `.merge` we update
    /// the existing record only if the import is newer.
    private func mergeBook(_ exported: ExportedBook, strategy: ImportStrategy) {

        let existingBook = fetchBook(id: exported.id)

        switch strategy {
        case .replace:
            let book = existingBook ?? Book(id: exported.id)
            applyExported(exported, to: book)
            if existingBook == nil { context.insert(book) }

        case .merge:
            if let existing = existingBook {
                let importedDate = exported.lastReadDate ?? .distantPast
                let existingDate = existing.lastReadDate ?? .distantPast
                if importedDate > existingDate {
                    applyExported(exported, to: existing)
                }
                mergeAnnotations(exported.annotations, into: existing.id)
            } else {
                let book = Book(id: exported.id)
                applyExported(exported, to: book)
                context.insert(book)
                mergeAnnotations(exported.annotations, into: book.id)
            }
        }
    }

    /// Merge annotations for one book — insert any missing IDs, leave
    /// existing IDs untouched.
    private func mergeAnnotations(_ snapshots: [SidecarAnnotation], into bookID: UUID) {
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingIDs = Set(existing.map { $0.id })

        for snap in snapshots where !existingIDs.contains(snap.id) {
            let annotation = Annotation(
                bookID: bookID,
                type: AnnotationType(rawValue: snap.type) ?? .highlight,
                chapterHref: snap.chapterHref,
                startOffset: snap.startOffset,
                endOffset: snap.endOffset,
                highlightColor: snap.highlightColor.flatMap(HighlightColor.init(rawValue:)),
                noteText: snap.noteText,
                bookmarkLabel: snap.bookmarkLabel
            )
            annotation.id = snap.id
            annotation.createdAt = snap.createdAt
            context.insert(annotation)
        }
    }

    /// Merge a Collection record — replace mode rebuilds, merge mode
    /// upserts.
    private func mergeCollection(_ exported: ExportedCollection, strategy: ImportStrategy) {
        let descriptor = FetchDescriptor<Collection>(
            predicate: #Predicate { $0.id == exported.id }
        )
        let existing = (try? context.fetch(descriptor))?.first

        let target = existing ?? Collection()
        target.id = exported.id
        target.name = exported.name
        target.isSmartCollection = exported.isSmartCollection
        target.smartFilterRaw = exported.smartFilter
        target.bookIDs = exported.bookIDs
        target.dateCreated = exported.dateCreated
        target.sortOrder = exported.sortOrder
        if existing == nil { context.insert(target) }
    }

    // MARK: - Helpers

    private func fetchBook(id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func applyExported(_ exported: ExportedBook, to book: Book) {
        book.title = exported.title
        book.author = exported.author
        book.language = exported.language
        book.series = exported.series
        book.seriesNumber = exported.seriesNumber
        book.fileSHA256 = exported.fileHash
        book.dateAdded = exported.dateAdded
        book.lastReadDate = exported.lastReadDate
        book.readingProgress = exported.readingProgress
        book.isFinished = exported.isFinished
        book.customEndPoint = exported.customEndPoint
        book.didNotFinish = exported.didNotFinish
        book.storageLocationRaw = exported.storageLocation
        if let pos = exported.readingPosition {
            book.lastChapterHref = pos.chapterHref
            book.lastScrollOffset = pos.scrollOffset
        }
    }
}
