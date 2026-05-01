//
//  EpubLoader.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Readium-backed epub loader used by the *reader*. Opens an epub
//  via the Readium Swift Toolkit, starts a local HTTP server that
//  serves the publication's resources, and returns a `ParsedEpub`
//  whose spine items carry localhost URLs the WKWebView can load
//  directly via `load(URLRequest:)`.
//
//  WHY THIS EXISTS ALONGSIDE EpubParser:
//  EpubParser (Codex Reader/EpubParser/) is the original custom parser
//  used by IngestionPipeline at ingest time. The reader has been moved
//  to Readium because Readium has already solved the malformed-epub
//  edge cases the custom parser would otherwise accumulate workarounds
//  for. Ingestion stays on EpubParser for now to keep this branch's
//  blast radius small — see CLAUDE.md "Ingestion still on the custom
//  epub parser" handoff note for the migration plan.
//
//  WHY GCDHTTPServer (DEPRECATED):
//  Readium's `GCDHTTPServer` is marked `@available(*, deprecated)` in
//  3.x because Readium's own navigators have moved to a
//  `WKURLSchemeHandler` with a custom `readium://` scheme. We're using
//  the deprecated server anyway for two reasons: (1) it gives us
//  localhost URLs that drop into existing `WKWebView.load` call sites
//  unchanged, (2) the alternative — building our own URL scheme
//  handler — is ~50–80 LOC of bridging code that doesn't earn its keep
//  for a proof-of-concept. Migration plan documented in CLAUDE.md
//  "Readium GCDHTTPServer is deprecated" handoff note.
//
//  PINNED VERSION:
//  Readium Swift Toolkit 3.8.0 (March 2026). The async Asset/Publication
//  API used here was introduced in Readium 3.0; signatures have been
//  stable across 3.x minor versions.
//

import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumAdapterGCDWebServer

// MARK: - Errors

enum EpubLoaderError: LocalizedError {
    case invalidURL(URL)
    case assetRetrieve(AssetRetrieveURLError)
    case publicationOpen(PublicationOpenError)
    case serverFailedToServe(Error)
    case noReadingOrder

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "This file's URL isn't one Readium can open."
        case .assetRetrieve:        return "Couldn't read this epub file."
        case .publicationOpen:      return "Couldn't open this epub — it may be malformed or unsupported."
        case .serverFailedToServe:  return "Couldn't start the local content server."
        case .noReadingOrder:       return "This epub has no reading order."
        }
    }
}

// MARK: - Loader

/// Opens an epub via Readium and serves its resources to a WKWebView
/// via a local HTTP server. One instance per open book — `close()`
/// when the reader dismisses.
@MainActor
final class EpubLoader {

    // The retriever is shared between asset loading and the HTTP
    // server (the server reuses it to fetch resources on request).
    private let assetRetriever: AssetRetriever
    private let publicationOpener: PublicationOpener

    /// The HTTP server that hosts this book's resources at a localhost
    /// URL. Held for the life of the reading session; `close()` tears
    /// it down.
    private var server: GCDHTTPServer?

    /// The opened publication. Held so that the HTTP server's resource
    /// handler keeps working — the server holds the publication weakly
    /// in some configurations.
    private var publication: Publication?

    init() {
        let httpClient = DefaultHTTPClient()
        self.assetRetriever = AssetRetriever(httpClient: httpClient)
        self.publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
    }

    /// Open the epub at `epubFileURL` and start the HTTP server.
    /// Returns a `ParsedEpub` populated with localhost URLs.
    ///
    /// - Throws: `EpubLoaderError` on retrieve / open / serve failure.
    func open(_ epubFileURL: URL) async throws -> ParsedEpub {

        // 1. Convert the Foundation URL into Readium's AbsoluteURL form.
        guard let absoluteURL = AnyURL(url: epubFileURL).absoluteURL else {
            throw EpubLoaderError.invalidURL(epubFileURL)
        }

        // 2. Retrieve the asset (a file Asset, in our case — the epub on
        //    disk). Readium sniffs the format itself.
        let asset: Asset
        switch await assetRetriever.retrieve(url: absoluteURL) {
        case .success(let result):
            asset = result
        case .failure(let error):
            throw EpubLoaderError.assetRetrieve(error)
        }

        // 3. Open the publication — Readium parses the epub into its
        //    Publication object (manifest, reading order, resources).
        //    `allowUserInteraction: false` because we don't prompt for
        //    DRM credentials in the reader path; DRM-protected epubs
        //    are refused at ingest time.
        let pub: Publication
        switch await publicationOpener.open(
            asset: asset,
            allowUserInteraction: false
        ) {
        case .success(let result):
            pub = result
        case .failure(let error):
            throw EpubLoaderError.publicationOpen(error)
        }

        guard !pub.readingOrder.isEmpty else {
            throw EpubLoaderError.noReadingOrder
        }

        // 4. Start the HTTP server and serve this publication's
        //    resources at a unique endpoint per book session. Using a
        //    UUID avoids endpoint collisions if the server is reused
        //    across books in a future iteration.
        let server = GCDHTTPServer(assetRetriever: assetRetriever)
        let endpoint = "codex/\(UUID().uuidString.lowercased())"
        let baseURL: HTTPURL
        do {
            baseURL = try server.serve(at: endpoint, publication: pub)
        } catch {
            throw EpubLoaderError.serverFailedToServe(error)
        }

        self.server = server
        self.publication = pub

        // 5. Build the ParsedEpub. Spine, metadata, and TOC come from
        //    Readium; chapter URLs are resolved against the server's
        //    base URL.
        let toc = await readTOC(from: pub)
        return makeParsedEpub(from: pub, baseURL: baseURL, toc: toc)
    }

    /// Stop the HTTP server and release the publication. Call when the
    /// reader closes the book.
    func close() {
        server = nil   // GCDHTTPServer stops on dealloc.
        publication = nil
    }

    // MARK: - ParsedEpub builder

    private func makeParsedEpub(
        from pub: Publication,
        baseURL: HTTPURL,
        toc: [ParsedEpub.TocEntry]
    ) -> ParsedEpub {

        // The spine in Readium parlance is `readingOrder`. Each Link's
        // `href` is a relative URL string (e.g. "EPUB/text/chap01.xhtml").
        // We resolve each href against the server's base URL to get a
        // localhost URL the WKWebView can load.
        let spine: [ParsedEpub.SpineItem] = pub.readingOrder.enumerated().compactMap { index, link in
            guard let chapterURL = resolveChapterURL(href: link.href, baseURL: baseURL) else {
                return nil
            }
            // Readium doesn't surface epub's `linear="no"` directly on
            // Link in 3.x — assume `linear: true` for everything in
            // readingOrder. Non-linear items live outside readingOrder
            // anyway, so this is correct in practice.
            return ParsedEpub.SpineItem(
                id: link.title ?? "spine-\(index)",
                href: link.href,
                absoluteURL: chapterURL,
                linear: true
            )
        }

        // Author: Readium exposes contributors with role "author" via
        // `metadata.authors`. Join multiple authors with ", " to match
        // EpubParser's behaviour.
        let author = pub.metadata.authors
            .map(\.name)
            .joined(separator: ", ")

        return ParsedEpub(
            title: pub.metadata.title ?? "",
            author: author,
            language: pub.metadata.languages.first ?? "en",
            // Cover extraction is an ingestion-time concern (still on
            // EpubParser); the reader doesn't read this field.
            coverImageURL: nil,
            spine: spine,
            tocEntries: toc,
            // The reader doesn't read manifestItems either — left empty.
            manifestItems: [:],
            // unzippedRoot is meaningless for HTTP-served content. We
            // set it to the server's base URL so any consumer that
            // happens to read it gets a non-nil URL; the only legitimate
            // consumer (IngestionPipeline cleanup) doesn't run on this
            // path.
            unzippedRoot: baseURL.url
        )
    }

    private func resolveChapterURL(href: String, baseURL: HTTPURL) -> URL? {
        // Standard URL relative-resolution: the href "EPUB/text/x.xhtml"
        // resolved against "http://127.0.0.1:46379/codex/abc/" gives
        // "http://127.0.0.1:46379/codex/abc/EPUB/text/x.xhtml".
        return URL(string: href, relativeTo: baseURL.url)?.absoluteURL
    }

    private func readTOC(from pub: Publication) async -> [ParsedEpub.TocEntry] {
        switch await pub.tableOfContents() {
        case .success(let links):
            return links.map { tocEntry(from: $0) }
        case .failure:
            return []
        }
    }

    private func tocEntry(from link: Link) -> ParsedEpub.TocEntry {
        ParsedEpub.TocEntry(
            title: link.title ?? "Untitled",
            href: link.href,
            children: link.children.map { tocEntry(from: $0) }
        )
    }
}
