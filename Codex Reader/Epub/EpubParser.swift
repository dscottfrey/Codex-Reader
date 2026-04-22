//
//  EpubParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Parses an epub file into the typed `ParsedEpub` value used by the
//  rendering, library, and ingestion modules.
//
//  WHY IT'S A STUB RIGHT NOW:
//  The directive (Module 1, Open Questions §8) leaves the parser choice
//  for a technical spike: ReadiumSDK vs FolioReaderKit vs custom Swift
//  code. We can't pick that here without test epubs in front of us.
//  The Codex coding rule (CLAUDE.md, "make the simplest reasonable choice
//  and TODO it") applies: this file lays out the API every other module
//  expects, but the implementation throws `parserNotImplemented`. The
//  app builds; the reader will show a clear error when asked to open a
//  book until this is filled in.
//
//  TODO (Module 1 §8 spike): replace the stub with a real parser. The
//  recommended order:
//    1. Try a minimal custom XML parser using XMLParser (Foundation).
//       OPF and NCX/Nav are simple XML — small surface area.
//    2. If custom proves fiddly with edge-case epubs, evaluate
//       ReadiumSDK as a SwiftPM dependency.
//    3. Each parser must expose the same API as `EpubParser.parse(_:)`
//       below so the rest of the app doesn't change.
//

import Foundation

enum EpubParserError: Error {
    case parserNotImplemented
    case malformedContainer
    case opfNotFound
    case malformedOPF
}

/// Parse an epub at a local file URL into the typed `ParsedEpub`.
enum EpubParser {

    /// Parse the epub at `url` and return its metadata, spine, and TOC.
    ///
    /// Steps when fully implemented (per directive §3.2):
    ///   1. Unzip via `EpubArchive.unzip(_:)`.
    ///   2. Read `META-INF/container.xml` to find the OPF path.
    ///   3. Parse the OPF for metadata, manifest, and spine.
    ///   4. Parse the NCX (epub2) or Navigation Document (epub3) for TOC.
    ///   5. Resolve cover image href if declared.
    static func parse(_ url: URL) throws -> ParsedEpub {
        // The unzip step itself will throw `notImplemented` until the
        // technical spike resolves the parser/archive question. Surfacing
        // a separate error here makes the call-site error messages
        // clearer — "epub parser not implemented" reads better than
        // "epub archive not implemented" when the failure is wider than
        // just unzipping.
        _ = try EpubArchive.unzip(url)
        throw EpubParserError.parserNotImplemented
    }

    /// Best-effort metadata extraction without doing a full parse — used
    /// at ingestion time by the duplicate detector and to fill in a
    /// minimal book record before the user opens the book.
    ///
    /// The simplest reasonable fallback is to derive title/author from
    /// the filename (Ingestion Engine §7 specifies the canonical
    /// "Author Last, First - Title.epub" convention). Once the real
    /// parser lands this can read OPF metadata directly.
    static func quickMetadata(from url: URL) -> EpubMetadata {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: " - ")
        let author: String
        let title: String
        if parts.count >= 2 {
            author = parts[0]
            title  = parts.dropFirst().joined(separator: " - ")
        } else {
            author = "Unknown Author"
            title  = stem
        }
        return EpubMetadata(
            title: title,
            author: author,
            language: "en",
            publisher: nil,
            epubVersion: "3.0",
            coverHref: nil
        )
    }
}
