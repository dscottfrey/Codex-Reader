//
//  EpubParserError.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The typed errors the parser throws when a file is genuinely
//  unreadable. Rendering Engine directive §3.2.
//
//  THE SPEC PHILOSOPHY — DEGRADE GRACEFULLY, THROW ONLY FOR FATAL CASES:
//  A partially-parseable epub is better than a crash. The parser does
//  its best to fill in optional fields (missing cover → nil; missing
//  TOC → synthesised from the spine; missing language → default `"en"`).
//  Only four cases are severe enough to fail the whole parse:
//    1. The ZIP wouldn't extract at all.
//    2. `META-INF/container.xml` is missing (not a real epub).
//    3. The OPF referenced by container.xml isn't on disk.
//    4. The spine has zero entries — there's literally nothing to read.
//

import Foundation

enum EpubParserError: Error, LocalizedError {

    /// The ZIP extraction failed. The file is corrupt, encrypted, or
    /// uses a compression method we don't support.
    case unzipFailed

    /// `META-INF/container.xml` is missing. Without it we can't find
    /// the OPF, and without the OPF there's no spine.
    case containerXmlNotFound

    /// `container.xml` gave us an OPF path, but no file exists at that
    /// path after extraction. The epub is malformed or half-downloaded.
    case opfNotFound

    /// The spine parsed to an empty list. An epub with no readable
    /// chapters is by definition unreadable.
    case spineEmpty

    /// Plain-English message for surfacing to the user. Matches the
    /// Ingestion Engine's voice — short, factual, no blame.
    var errorDescription: String? {
        switch self {
        case .unzipFailed:
            return "This epub file couldn't be opened — the archive appears to be damaged."
        case .containerXmlNotFound:
            return "This file is missing its epub container and can't be read."
        case .opfNotFound:
            return "This epub is missing its package document and can't be read."
        case .spineEmpty:
            return "This epub has no readable chapters."
        }
    }
}
