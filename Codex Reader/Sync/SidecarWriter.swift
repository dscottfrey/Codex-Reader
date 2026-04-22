//
//  SidecarWriter.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Writes a book's reading state out to its `.codex` sidecar file in
//  iCloud Drive. Defined in Module 4 (Sync Engine) §12.
//
//  WHY ITS OWN FILE:
//  Sidecar writing happens at several lifecycle moments — chapter
//  turn, 30-second timer, app background, book close. Centralising the
//  write logic means each caller is one line: `SidecarWriter.write(for:
//  book, in: context)`.
//
//  WHY ASYNC ISN'T NEEDED:
//  The directive (§12.2) notes a heavily-annotated book produces ~30-50KB
//  of JSON. JSONEncoder + a single Data write is microseconds — no
//  reason to push this off the main thread.
//

import Foundation
import SwiftData

@MainActor
enum SidecarWriter {

    /// Write the sidecar file for the given book. Silently does
    /// nothing if no destination URL can be resolved (e.g., iCloud is
    /// unavailable) — sidecars are best-effort.
    static func write(for book: Book, in context: ModelContext) {
        guard let url = sidecarURL(for: book) else { return }

        let sidecar = makeSidecar(book: book, context: context)
        guard let data = try? jsonEncoder.encode(sidecar) else { return }
        try? data.write(to: url, options: [.atomic])

        // Track the timestamp on the book record so the UI in Book
        // Details ("Sidecar last written: ...") can show it.
        book.sidecarLastWritten = sidecar.lastWritten
    }

    // MARK: - Path resolution

    /// Resolve the on-disk URL of the sidecar file for this book. The
    /// sidecar lives next to the epub in iCloud Drive (or in
    /// Application Support when the book is in `.localOnly` mode).
    private static func sidecarURL(for book: Book) -> URL? {
        let epubPath: String?
        switch book.storageLocation {
        case .iCloudDrive: epubPath = book.iCloudDrivePath
        case .localOnly:   epubPath = book.localFallbackPath
        }
        guard let path = epubPath else { return nil }

        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let sidecarName = SidecarFile.sidecarFilename(
            forEpubFilename: url.lastPathComponent
        )
        return dir.appendingPathComponent(sidecarName)
    }

    // MARK: - Build

    private static func makeSidecar(book: Book, context: ModelContext) -> SidecarFile {
        // Annotations are the Annotation System's responsibility. While
        // that module hasn't shipped its store, we collect from a fetch
        // by bookID — the @Model lookup is graceful when the table is
        // empty (returns []), so this is safe ahead of Module 6.
        let annotations = fetchAnnotationSnapshots(for: book.id, in: context)

        return SidecarFile(
            formatVersion: 1,
            lastWritten: Date(),
            bookID: book.id,
            title: book.title,
            author: book.author,
            chapterHref: book.lastChapterHref,
            scrollOffset: book.lastScrollOffset,
            readingProgress: book.readingProgress,
            isFinished: book.isFinished,
            customEndPoint: book.customEndPoint,
            didNotFinish: book.didNotFinish,
            didNotFinishDate: book.didNotFinishDate,
            annotations: annotations
        )
    }

    /// Fetch annotation snapshots for this book. Returns [] if the
    /// Annotation @Model is not yet registered in the schema (which is
    /// true until Module 6 lands) — a graceful no-op rather than a
    /// crash.
    private static func fetchAnnotationSnapshots(for bookID: UUID, in context: ModelContext) -> [SidecarAnnotation] {
        // Use a typed FetchDescriptor against the Annotation type. If
        // it's not in the schema yet, we catch and return [].
        do {
            let descriptor = FetchDescriptor<Annotation>(
                predicate: #Predicate { $0.bookID == bookID && $0.deletedAt == nil }
            )
            let results = try context.fetch(descriptor)
            return results.map(toSnapshot)
        } catch {
            return []
        }
    }

    /// Convert a SwiftData Annotation into the JSON-friendly snapshot.
    private static func toSnapshot(_ a: Annotation) -> SidecarAnnotation {
        SidecarAnnotation(
            id: a.id,
            type: a.type.rawValue,
            chapterHref: a.chapterHref,
            startOffset: a.startOffset,
            endOffset: a.endOffset,
            highlightColor: a.highlightColor?.rawValue,
            noteText: a.noteText,
            bookmarkLabel: a.bookmarkLabel,
            createdAt: a.createdAt
        )
    }

    /// Pretty-printed encoder so sidecar files are readable in Finder
    /// or any text editor — useful for the "your data is yours"
    /// philosophy of §11 and §12.
    private static var jsonEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
