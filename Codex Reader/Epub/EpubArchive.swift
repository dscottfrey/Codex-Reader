//
//  EpubArchive.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Unzips an epub file (which is just a ZIP archive) into a working
//  directory. Used by the parser, the ingestion pipeline, and DRM
//  detection.
//
//  WHY APPLE'S OWN UNZIP:
//  iOS doesn't expose a public Foundation ZIP API. We use Apple's own
//  `Compression` framework via NSFileCoordinator + the system Archive
//  utility, but neither gives a clean ZIP-extract-to-directory primitive.
//
//  WHAT WE'RE DOING INSTEAD:
//  iOS 14+ introduced FileProvider's `Archive` framework but it only
//  reads .aar files. The simplest working approach we've found that
//  doesn't require a third-party library is to use NSFileCoordinator with
//  `Foundation.Process` — but Process is unavailable on iOS.
//
//  THE ACCEPTED COMPROMISE FOR THIS SCAFFOLDING:
//  We expose a minimal ZIP-extraction API as a stub. The directive (Open
//  Questions §8) explicitly defers this decision to a "technical spike."
//  Two viable real implementations:
//    1. Add the apple/swift-system + apple/swift-collections packages and
//       use libcompression with a hand-written ZIP central-directory
//       reader (no external dep).
//    2. Adopt a small open-source dep like ZIPFoundation (MIT licence,
//       no transitive deps).
//  TODO: Make the parser-vs-library decision (directive §3.2 spike) and
//  replace this stub with a working ZIP reader. Until then ingestion will
//  fail with `EpubArchiveError.notImplemented`.
//

import Foundation

enum EpubArchiveError: Error {
    /// Raised by the placeholder unzip path. See file header.
    case notImplemented
    /// The file at the given URL is not a valid ZIP archive.
    case notAZipArchive
    /// We couldn't write to the destination directory.
    case extractionFailed(underlying: Error)
}

/// Unzip an epub (ZIP archive) into a temporary working directory and
/// return the URL of that directory.
///
/// Caller is responsible for cleaning the directory up when done — the
/// parser typically keeps it for the life of the open book and removes
/// it on close.
enum EpubArchive {

    /// Create a fresh subdirectory inside the app's caches directory and
    /// extract the epub into it.
    ///
    /// - Parameter epubURL: Local file URL of the .epub.
    /// - Returns: URL of the directory containing the unzipped contents.
    static func unzip(_ epubURL: URL) throws -> URL {

        // Build a fresh working directory keyed by the epub's filename
        // and a UUID so two concurrent ingestions never collide.
        let workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexEpub", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: workRoot,
            withIntermediateDirectories: true
        )

        // ─────────────────────────────────────────────────────────────
        // The actual ZIP read is the open question. Until the technical
        // spike resolves it we throw `notImplemented`. Callers — the
        // ingestion pipeline and the DRM detector — handle this error by
        // surfacing the user-facing "couldn't read epub" message.
        //
        // When the real implementation lands it will:
        //   1. Open the ZIP central directory.
        //   2. For each entry, create the parent directory under workRoot
        //      and extract the file (DEFLATE or stored).
        //   3. Stop on any I/O error and surface it via .extractionFailed.
        // ─────────────────────────────────────────────────────────────
        _ = workRoot
        throw EpubArchiveError.notImplemented
    }

    /// Read a single file out of the ZIP archive without extracting the
    /// whole thing. Used by DRM detection, which only needs to know
    /// whether `META-INF/encryption.xml` exists and what's in it.
    ///
    /// TODO: Implement alongside `unzip(_:)` in the technical spike. For
    /// now returns nil so DRM detection never blocks ingestion in the
    /// stub; ingestion will fail at the unzip step instead.
    static func readEntry(_ entryPath: String, from epubURL: URL) -> Data? {
        return nil
    }
}
