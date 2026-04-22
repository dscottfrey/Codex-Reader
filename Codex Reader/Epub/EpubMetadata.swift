//
//  EpubMetadata.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Plain Swift value types describing the parts of an epub Codex cares
//  about: the spine (reading order), the manifest (file list), the
//  metadata (title/author/cover), and the table of contents.
//
//  WHY IT EXISTS:
//  Whatever epub parser implementation we end up with (custom — see
//  EpubParser.swift — or a future third-party library) returns these
//  types. Pinning the surface here means the rest of the app doesn't
//  care which parser produced them.
//
//  WHAT'S DELIBERATELY ABSENT:
//  Anything epub-3 specific that isn't needed for v1. Media overlays,
//  forms, scripted interactivity — all out of scope.
//

import Foundation

/// A single chapter or content document in the epub spine.
struct EpubSpineItem: Codable, Identifiable, Hashable {

    /// The href as it appears in the OPF spine — relative to the OPF
    /// directory inside the epub. e.g. `OEBPS/chapter03.xhtml`.
    var id: String { href }

    /// Relative path inside the epub.
    let href: String

    /// True if this item is part of the main reading flow. False for
    /// supplementary material (footnotes, preview chapters). Used by the
    /// Sync Engine's "Finished?" auto-detection in directive §13.6.
    let linear: Bool

    /// MIME type from the manifest, e.g. `application/xhtml+xml`.
    let mediaType: String
}

/// One item in the table of contents. May have nested children.
struct EpubTOCItem: Codable, Identifiable, Hashable {

    var id: String { href + title }

    /// Display name (chapter title, section heading, etc.).
    let title: String

    /// Spine href to navigate to when the user taps this entry.
    let href: String

    /// Nested TOC entries — sub-sections, sub-chapters.
    let children: [EpubTOCItem]
}

/// All the metadata Codex extracts from an epub at ingestion time.
struct EpubMetadata: Codable {

    let title: String
    let author: String

    /// IETF BCP 47 language code, e.g. `en`, `en-US`, `fr`. Defaults to
    /// `en` when the epub doesn't declare a language (rare but happens).
    let language: String

    /// Publisher name from the OPF metadata, when present.
    let publisher: String?

    /// "2.0" or "3.0" — used to choose between EPUB 2 (NCX) and EPUB 3
    /// (Navigation Document) TOC parsing paths.
    let epubVersion: String

    /// Path inside the epub to the cover image, when one is declared in
    /// the manifest (`properties="cover-image"`) or guessed from common
    /// fallback locations. nil → the cover extractor falls back to a
    /// generated placeholder.
    let coverHref: String?
}

/// The fully-parsed epub — metadata, spine, and TOC together. Returned
/// by EpubParser.parse(:).
struct ParsedEpub {
    let metadata: EpubMetadata
    let spine: [EpubSpineItem]
    let toc: [EpubTOCItem]

    /// The directory where the epub's contents have been unzipped.
    /// Chapter file URLs are computed by joining this with a spine href.
    let unzippedRoot: URL

    /// Path within `unzippedRoot` to the directory the OPF document
    /// lives in. Spine hrefs are relative to this directory.
    let opfRelativeRoot: String
}
