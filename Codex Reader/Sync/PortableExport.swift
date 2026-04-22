//
//  PortableExport.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The "your data is yours" backup — generates a JSON file containing
//  every book record, its annotations, the user's reader settings, and
//  collections. Defined in Module 4 (Sync Engine) §11.
//
//  WHY ITS OWN FILE:
//  This is the canonical answer to "what happens to my data if CloudKit
//  fails or I leave Apple." Per the directive philosophy (§11.1): the
//  user owns the export, stores it where they want, and can re-import
//  it without Codex being available. Keeping the format here in one
//  place means the schema is documented in code as well as in the
//  directive.
//
//  WHY IT'S A PURE STRUCT (NOT a SwiftData @Model):
//  A backup is a snapshot in time, not a synced live record. We
//  encode it from the live SwiftData store at export time and decode
//  it back during import.
//

import Foundation
import SwiftData

/// The top-level shape of a Codex Library Export. Layout matches
/// directive §11.2.
struct PortableExport: Codable {

    let exportVersion: Int
    let exportDate: Date
    let exportedBy: String

    let books: [ExportedBook]
    let readerSettings: ReaderSettings
    let collections: [ExportedCollection]

    // MARK: - Build

    /// Snapshot the current SwiftData state into an export.
    @MainActor
    static func snapshot(from context: ModelContext) -> PortableExport {

        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let annotations = (try? context.fetch(FetchDescriptor<Annotation>())) ?? []
        let collections = (try? context.fetch(FetchDescriptor<Collection>())) ?? []
        let settings = ReaderSettingsRecord.current(in: context).settings

        let exportedBooks = books.map { book in
            let bookAnnotations = annotations.filter { $0.bookID == book.id && $0.deletedAt == nil }
            return ExportedBook(from: book, annotations: bookAnnotations)
        }

        let exportedCollections = collections.map(ExportedCollection.init(from:))

        return PortableExport(
            exportVersion: 1,
            exportDate: Date(),
            exportedBy: "Codex v1.0",
            books: exportedBooks,
            readerSettings: settings,
            collections: exportedCollections
        )
    }

    /// Encode the export to a Data blob ready to be written to disk
    /// or shared via the system share sheet.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// Snapshot of one Book inside the export. Keeps the JSON compact and
/// portable — only the fields a future Codex (or a power-user reading
/// the file) needs.
struct ExportedBook: Codable {

    let id: UUID
    let title: String
    let author: String
    let language: String
    let series: String?
    let seriesNumber: Double?
    let fileHash: String?
    let dateAdded: Date
    let lastReadDate: Date?
    let readingProgress: Double
    let isFinished: Bool
    let customEndPoint: Double?
    let didNotFinish: Bool
    let storageLocation: String

    /// Reading position. Optional in case the book has never been
    /// opened.
    let readingPosition: ExportedReadingPosition?

    let annotations: [SidecarAnnotation]

    init(from book: Book, annotations: [Annotation]) {
        self.id = book.id
        self.title = book.title
        self.author = book.author
        self.language = book.language
        self.series = book.series
        self.seriesNumber = book.seriesNumber
        self.fileHash = book.fileSHA256
        self.dateAdded = book.dateAdded
        self.lastReadDate = book.lastReadDate
        self.readingProgress = book.readingProgress
        self.isFinished = book.isFinished
        self.customEndPoint = book.customEndPoint
        self.didNotFinish = book.didNotFinish
        self.storageLocation = book.storageLocation.rawValue

        if let href = book.lastChapterHref {
            self.readingPosition = ExportedReadingPosition(
                chapterHref: href,
                scrollOffset: book.lastScrollOffset,
                lastUpdated: book.lastReadDate ?? book.dateAdded
            )
        } else {
            self.readingPosition = nil
        }

        self.annotations = annotations.map {
            SidecarAnnotation(
                id: $0.id,
                type: $0.type.rawValue,
                chapterHref: $0.chapterHref,
                startOffset: $0.startOffset,
                endOffset: $0.endOffset,
                highlightColor: $0.highlightColor?.rawValue,
                noteText: $0.noteText,
                bookmarkLabel: $0.bookmarkLabel,
                createdAt: $0.createdAt
            )
        }
    }
}

/// One reading position entry inside an exported book.
struct ExportedReadingPosition: Codable {
    let chapterHref: String
    let scrollOffset: Double
    let lastUpdated: Date
}

/// One Collection inside the export.
struct ExportedCollection: Codable {

    let id: UUID
    let name: String
    let isSmartCollection: Bool
    let smartFilter: String?
    let bookIDs: [UUID]
    let dateCreated: Date
    let sortOrder: Int

    init(from collection: Collection) {
        self.id = collection.id
        self.name = collection.name
        self.isSmartCollection = collection.isSmartCollection
        self.smartFilter = collection.smartFilter?.rawValue
        self.bookIDs = collection.bookIDs
        self.dateCreated = collection.dateCreated
        self.sortOrder = collection.sortOrder
    }
}
