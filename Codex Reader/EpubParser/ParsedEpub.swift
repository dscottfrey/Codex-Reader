//
//  ParsedEpub.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The typed output of EpubParser.parse(_:) — the fully parsed
//  representation of an epub file that every downstream module (Rendering
//  Engine, Ingestion Engine, Library Manager) consumes. Defined by
//  Rendering Engine directive §3.2.
//
//  WHY THE SHAPE IS WHAT IT IS:
//  The directive §3.2 spec lists: title, author, language, coverImageURL,
//  spine, tocEntries, manifestItems. Two pragmatic additions that the
//  spec doesn't list but the rest of the app needs:
//
//    1. `unzippedRoot` — WKWebView's loadFileURL(_:allowingReadAccessTo:)
//       needs the parent directory so it can resolve each chapter's
//       relative asset references (CSS, images, fonts). Callers also
//       need it so they can clean up the temp directory when the book
//       is closed (§3.2 "Temp directory lifetime").
//
//    2. `linear` on SpineItem — a standard epub spine attribute that
//       tells the Sync Engine's "Finished?" auto-detection whether an
//       item is part of the main reading flow or supplementary content.
//       Including it costs nothing and keeps the existing logic working
//       without a second pass through the manifest.
//
//  Both are documented inline as judgment calls.
//

import Foundation

/// A fully parsed epub. Produced once by `EpubParser.parse(_:)` and held
/// by the Reader view model for the life of the reading session.
struct ParsedEpub {

    // MARK: - Metadata (directive §3.2 Step 3)

    /// `<dc:title>` from the OPF. Required.
    let title: String

    /// `<dc:creator>` from the OPF. Multiple creators are joined with
    /// `, `. Empty string only if the OPF genuinely had no creator tag.
    let author: String

    /// `<dc:language>`. IETF BCP 47 code, e.g. `en`, `fr`, `ar`. Used by
    /// the Rendering Engine for right-to-left detection. Defaults to
    /// `"en"` when the OPF doesn't declare one (rare but legal).
    let language: String

    /// Absolute path inside the unzipped temp directory to the cover
    /// image, when the OPF declared one. nil → cover extractor falls
    /// back to a generated placeholder (Ingestion §5.4).
    let coverImageURL: URL?

    // MARK: - Reading structure (directive §3.2 Steps 3 & 4)

    /// The ordered reading sequence as declared by `<spine>`.
    let spine: [SpineItem]

    /// Table of contents — from the epub 3 nav document, the epub 2 NCX,
    /// or synthesised from the spine if neither is present.
    let tocEntries: [TocEntry]

    /// Every manifest item keyed by its manifest id. Lets the Annotation
    /// System and the Rendering Engine resolve an id to a file without
    /// re-parsing the OPF.
    let manifestItems: [String: ManifestItem]

    // MARK: - Working directory (judgment call, see file header)

    /// The directory the epub was unzipped into. Chapter URLs sit under
    /// this root. Callers are responsible for cleaning it up when the
    /// book is closed.
    let unzippedRoot: URL

    // MARK: - Nested types

    /// One entry in the spine — one chapter (or front-matter /
    /// back-matter item).
    struct SpineItem {
        /// Manifest id referenced by the spine's `idref` attribute.
        let id: String

        /// Path as it appears in the manifest — relative to the OPF
        /// directory. Retained for logging and debug output.
        let href: String

        /// Full path inside `unzippedRoot`, already resolved so that
        /// loading a chapter is `webView.loadFileURL(absoluteURL, ...)`.
        let absoluteURL: URL

        /// `linear="yes"` (default) or `linear="no"`. Supplementary
        /// items — footnotes, preview chapters — are `linear == false`.
        /// Judgment call: not in the directive's struct but needed by the
        /// Sync Engine (see file header).
        let linear: Bool
    }

    /// One entry in the TOC. May have children for hierarchical TOCs.
    struct TocEntry {
        /// Display title, e.g. "Chapter 1: The Beginning".
        let title: String

        /// Target href. May include a fragment such as
        /// `chapter03.xhtml#section2`.
        let href: String

        /// Nested entries for sub-sections.
        let children: [TocEntry]
    }

    /// One file declared in the manifest. Covers every asset — chapter
    /// XHTML, CSS, images, fonts, the NCX/nav doc, the cover.
    struct ManifestItem {
        /// Manifest id (referenced by the spine and by `<meta
        /// name="cover">` in epub 2).
        let id: String

        /// Path relative to the OPF directory.
        let href: String

        /// MIME type, e.g. `application/xhtml+xml`, `image/jpeg`.
        let mediaType: String

        /// Full path inside `unzippedRoot`, pre-resolved.
        let absoluteURL: URL
    }
}
