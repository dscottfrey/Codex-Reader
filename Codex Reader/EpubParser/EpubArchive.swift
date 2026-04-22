//
//  EpubArchive.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Opens an epub (which is a ZIP file) and either extracts the whole
//  thing to a temp directory or pulls out a single entry. Used by the
//  parser (full extraction), the Ingestion Engine's DRM detector
//  (single-entry read of META-INF/encryption.xml), and the cover
//  extractor.
//
//  WHY THIS FILE DEVIATES FROM THE LITERAL DIRECTIVE:
//  Rendering Engine directive §3.2 shows this ZIP extraction done via
//  `Process()` invoking `/usr/bin/unzip`. That code is written for
//  macOS — `Foundation.Process` is not available in the iOS SDK and
//  there is no `unzip` binary inside the iOS sandbox, so the literal
//  code will not compile for the iPhone/iPad target. Confirmed by
//  attempting to typecheck it against `-sdk iphoneos`.
//
//  THE SPIRIT OF THE DIRECTIVE IS: "Don't pull in a zip library just for
//  archive extraction — use what's already on the system." On iOS, what's
//  already on the system is Foundation's `Compression` framework: it
//  exposes raw DEFLATE decompression (the only compression format epub
//  files use in practice, plus "stored" / no compression). The ZIP
//  container around the deflate streams is a tiny, stable binary format
//  that can be read in a few dozen lines. So: native `Compression`
//  framework + hand-rolled ZIP Central Directory reader, no external
//  dependency. That honours the spec's intent (§6.6 "minimize external
//  dependencies") better than the literal code would.
//
//  WHAT THIS HANDLES:
//  - ZIP "Stored" (method 0): raw copy, no compression.
//  - ZIP "Deflate" (method 8): the overwhelmingly common case.
//  - ZIP64 (archives over 4 GB) is out of scope. Every sensible epub
//    fits in 32-bit offsets; if we meet a 4 GB epub in the wild we'll
//    revisit.
//

import Foundation
import Compression

enum EpubArchive {

    // MARK: - Public API

    /// Extract an entire epub into a fresh UUID-keyed subdirectory inside
    /// the system temp directory and return the root URL.
    ///
    /// The caller is responsible for cleaning the directory up when the
    /// book is closed — the parser does not own its lifetime (directive
    /// §3.2 "Temp directory lifetime").
    static func unzip(_ epubURL: URL) throws -> URL {
        // One fresh directory per unzip, so concurrent ingestions never
        // collide. Keyed by UUID, not by epub filename, so two copies of
        // the same book being ingested at the same time stay isolated.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexEpub", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        try unzip(epubURL, to: destination)
        return destination
    }

    /// Overload that extracts into a caller-supplied directory — this is
    /// the shape the directive's §3.2 code block uses, kept as-is to
    /// match the spec's signature as closely as platform limits allow.
    static func unzip(_ epubURL: URL, to destinationURL: URL) throws {
        guard let data = try? Data(contentsOf: epubURL, options: .mappedIfSafe) else {
            throw EpubParserError.unzipFailed
        }

        let entries: [ZipEntry]
        do {
            entries = try ZipReader.readCentralDirectory(data)
        } catch {
            throw EpubParserError.unzipFailed
        }

        for entry in entries {
            // Directory entries (zero-size, filename ending in "/") only
            // need their directory created — no file contents to write.
            let entryURL = destinationURL.appendingPathComponent(entry.filename)

            if entry.filename.hasSuffix("/") {
                try? FileManager.default.createDirectory(
                    at: entryURL,
                    withIntermediateDirectories: true
                )
                continue
            }

            // Make sure the parent directory exists before writing — ZIP
            // files aren't required to list directories explicitly.
            let parent = entryURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )

            do {
                let body = try ZipReader.readEntryData(entry, from: data)
                try body.write(to: entryURL)
            } catch {
                // A single corrupt entry fails the whole extraction —
                // partial unzips would mask real problems downstream.
                throw EpubParserError.unzipFailed
            }
        }
    }

    /// Read a single named entry out of the ZIP without extracting
    /// anything to disk. Used by the DRM detector (which only needs
    /// `META-INF/encryption.xml`) and by any fast-path metadata lookup
    /// that doesn't want to pay for a full extract.
    ///
    /// Returns nil if the entry is missing or the read fails — callers
    /// (the DRM detector in particular) treat "couldn't read" as "not
    /// DRM'd" rather than blocking ingestion of a probably-fine file.
    static func readEntry(_ entryPath: String, from epubURL: URL) -> Data? {
        guard let data = try? Data(contentsOf: epubURL, options: .mappedIfSafe),
              let entries = try? ZipReader.readCentralDirectory(data),
              let match = entries.first(where: { $0.filename == entryPath })
        else { return nil }
        return try? ZipReader.readEntryData(match, from: data)
    }
}
