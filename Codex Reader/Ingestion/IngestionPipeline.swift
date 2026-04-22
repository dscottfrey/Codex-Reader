//
//  IngestionPipeline.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The shared pipeline every incoming epub passes through, no matter
//  whether it arrived from an OPDS download, the iCloud Drive Inbox,
//  the share sheet, AirDrop, or the document picker. Defined in Module 2
//  (Ingestion Engine) §5.
//
//  WHY ONE PIPELINE:
//  All entry paths converge on the same logical sequence: validate,
//  detect DRM, dedupe, extract metadata + cover, copy into the canonical
//  storage location, write the SwiftData record. By centralising the
//  flow here, a future change to (say) the dedupe rules takes one edit,
//  not five.
//
//  WHAT'S NOT YET IMPLEMENTED:
//  The duplicate-prompt UI flow (resume / start over / add as new) per
//  §5.2 returns a `DuplicateMatch` from the checker but the caller is
//  responsible for showing the prompt. The pipeline reports the duplicate
//  and lets the caller decide; in this scaffolding we just refuse the
//  duplicate to keep the path simple.
//

import Foundation
import SwiftData
import CryptoKit

/// Orchestrates the validate → dedupe → extract → save sequence for a
/// single incoming epub.
@MainActor
struct IngestionPipeline {

    /// The model context to write the new Book record into.
    let context: ModelContext

    /// Ingest a local epub file. Returns the freshly-inserted Book on
    /// success.
    ///
    /// - Throws: `IngestionError` cases describing what went wrong.
    func ingest(epubAt sourceURL: URL) throws -> Book {

        // 1. ZIP / epub validity check. The directive (§5) says: if the
        //    file is a .zip, look inside for an .epub. We treat a file
        //    with .epub extension as authoritative — anything else is
        //    rejected. (Multi-epub-in-zip handling is the v1.1
        //    refinement.)
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "epub" else {
            throw IngestionError.notValidEpub
        }

        // 2. DRM detection — refuse straight away if Adobe ADEPT
        //    encryption is present.
        if DRMDetector.isDRMProtected(sourceURL) {
            throw IngestionError.drmProtected
        }

        // 3. SHA-256 of the file, used by the duplicate checker.
        let sha = sha256(of: sourceURL)

        // 4. Parse the epub for real metadata. This also unzips the
        //    file into a temp directory — the cover extractor uses
        //    that directory below, and we clean it up afterwards so
        //    we don't leak temp storage.
        let parsed: ParsedEpub
        do {
            parsed = try EpubParser.parse(sourceURL)
        } catch {
            // If the file parses to nothing usable, surface it as "not
            // a valid epub" — matches the ingestion voice (§6 / §9)
            // without exposing internal error shapes.
            throw IngestionError.notValidEpub
        }
        defer {
            // Ingestion only needs the unzipped tree long enough to
            // read metadata and the cover image. Unlike the reader —
            // which keeps the tree for the life of the reading session
            // — we tear it down as soon as the Book record is built.
            try? FileManager.default.removeItem(at: parsed.unzippedRoot)
        }

        // If the OPF was missing required fields, fall back to the
        // canonical "Author - Title.epub" filename convention (§7) so
        // we still have something to show in the library.
        let (fallbackAuthor, fallbackTitle) = filenameFallbackTitleAndAuthor(for: sourceURL)
        let title = parsed.title.isEmpty ? fallbackTitle : parsed.title
        let author = parsed.author.isEmpty ? fallbackAuthor : parsed.author

        // 5. Duplicate check.
        let dedupe = DuplicateChecker().check(
            title: title,
            author: author,
            sha256: sha,
            in: context
        )
        switch dedupe {
        case .none:
            break
        case .exactFile, .sameMetadataRecent, .sameMetadataOld:
            // Caller is expected to present the resume / start-over /
            // add-as-new prompt (§5.2). Until that UI is built we stop
            // here with a clear error rather than silently overwriting.
            throw IngestionError.duplicateDetected
        }

        // 6. Build the Book record.
        let book = Book(title: title, author: author)
        book.language       = parsed.language
        book.fileSHA256     = sha
        book.fileSize       = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
        book.dateAdded      = Date()
        book.typographyMode = .userDefaults  // safe default before first-open prompt (Rendering §7.2)

        // 7. Copy the epub to the canonical storage location and store
        //    the path on the record.
        let stored = try copyToLibrary(epubAt: sourceURL, for: book)
        book.iCloudDrivePath = stored

        // 8. Cover extraction — uses the already-unzipped tree via the
        //    ParsedEpub so we don't pay to unzip twice.
        let coverPath = CoverExtractor.extractCover(
            forBookID: book.id,
            title: book.title,
            author: book.author,
            from: parsed
        )
        book.coverCachePath = coverPath

        // 9. Save to SwiftData. CloudKit sync runs automatically via the
        //    container configuration (Sync Engine §10).
        context.insert(book)
        try? context.save()

        return book
    }

    // MARK: - Helpers

    /// Pull a (author, title) pair out of the canonical "Author Last,
    /// First - Title.epub" filename format (Ingestion §7). Used only as
    /// a last-resort fallback when the OPF was missing `<dc:title>` or
    /// `<dc:creator>` — real epubs always have these.
    private func filenameFallbackTitleAndAuthor(for url: URL) -> (author: String, title: String) {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts[0], parts.dropFirst().joined(separator: " - "))
        }
        return ("Unknown Author", stem)
    }

    /// Compute the SHA-256 of a file. Used for the exact-file dedupe
    /// branch in §5.2. nil only if the file can't be read.
    private func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Copy the epub into the canonical library location. The directive
    /// (§7) specifies `iCloud Drive/Codex/Library/{Author Last, First} -
    /// {Title}.epub`. While CloudKit/iCloud Drive containers aren't
    /// fully wired up yet, we drop the file into Application
    /// Support/Library/ as a local fallback and store the relative path.
    /// The iCloud path will be substituted in once the iCloud container
    /// is configured in the project (see TODO in Codex_ReaderApp.swift).
    private func copyToLibrary(epubAt sourceURL: URL, for book: Book) throws -> String {
        let libraryRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let libraryDir = libraryRoot.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: libraryDir,
            withIntermediateDirectories: true
        )

        let safeFilename = canonicalFilename(title: book.title, author: book.author)
        let destURL = libraryDir.appendingPathComponent(safeFilename)

        // If the destination exists (rare collision after sanitisation),
        // append a count suffix per directive guidance: "Title (2).epub".
        var finalDest = destURL
        var counter = 2
        while FileManager.default.fileExists(atPath: finalDest.path) {
            let stem = destURL.deletingPathExtension().lastPathComponent
            finalDest = libraryDir.appendingPathComponent("\(stem) (\(counter)).epub")
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: finalDest)
        } catch {
            throw IngestionError.underlying(error)
        }

        return finalDest.path
    }

    /// Build the canonical "Author - Title.epub" filename, stripping the
    /// characters illegal in filenames per directive §7.
    private func canonicalFilename(title: String, author: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:*?\"<>|")
        let cleanTitle  = title.components(separatedBy: illegal).joined(separator: "-")
        let cleanAuthor = author.components(separatedBy: illegal).joined(separator: "-")
        return "\(cleanAuthor) - \(cleanTitle).epub"
    }
}
