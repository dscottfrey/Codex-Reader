//
//  OPDSEntry.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Plain value types describing one OPDS feed entry — typically one
//  book on a remote server (Calibre-Web, COPS, Standard Ebooks, etc.).
//
//  WHY ITS OWN FILE:
//  Three pieces of code touch these types: the OPDSFeedParser (produces
//  them), the OPDSBrowserView (displays them), and the IngestionPipeline
//  (downloads them). Putting the types in one place means each can
//  evolve independently without dragging the others along.
//

import Foundation

/// A single book's worth of metadata returned by an OPDS feed.
struct OPDSEntry: Identifiable, Hashable {

    /// The entry's unique id from the Atom feed. Used for deduplication
    /// across paginated requests and as the SwiftUI list identifier.
    let id: String

    let title: String
    let author: String
    let series: String?

    /// Long-form description / summary. May be HTML in the source feed
    /// — display code should treat it as plain text or render the HTML
    /// safely.
    let summary: String?

    /// URL to fetch the cover image. Optional — many feeds don't include
    /// one, in which case the UI shows a placeholder.
    let coverURL: URL?

    /// URL of the actual epub file. Tapping Download fires off a fetch
    /// to this URL and then hands the result to the ingestion pipeline.
    let downloadURL: URL?
}

/// One page of OPDS results — the parser returns this, with optional
/// pagination links so the UI knows whether more results are available.
struct OPDSFeedPage {
    let entries: [OPDSEntry]
    /// URL of the "next" link in the feed, when present. Nil → no more
    /// pages to fetch.
    let nextPageURL: URL?
}
