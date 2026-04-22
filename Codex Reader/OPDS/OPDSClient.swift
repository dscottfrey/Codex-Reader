//
//  OPDSClient.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Fetches OPDS feeds and individual epub downloads from a configured
//  BookSource. Defined alongside Module 2 §2.3 (search-first UI) — this
//  is the network half; the UI half lives in OPDSBrowserView.
//
//  WHY URLSession DIRECTLY:
//  OPDS is plain HTTP with optional Basic Auth. URLSession + a small
//  amount of glue is all we need; pulling in Alamofire or similar would
//  violate the "no external dependencies" rule (CLAUDE.md / directive
//  §6.6).
//
//  WHAT'S NOT YET HERE:
//  - Search via OpenSearch (the directive §2.3 calls for OpenSearch
//    queries; in this scaffolding we just GET the source's root feed).
//  - Lazy pagination (we expose `nextPageURL` from each fetched page so
//    the UI can request the next page on scroll, but the iterator loop
//    isn't wired up yet).
//  - Credential lookup from Keychain — the auth header construction is
//    here, but the Keychain helper is a Settings module file that
//    hasn't been written yet. The source's `requiresAuth` flag governs
//    the path.
//

import Foundation

/// Network errors specific to OPDS interactions.
enum OPDSError: Error, LocalizedError {
    case sourceUnreachable
    case invalidResponse
    case parseFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .sourceUnreachable:
            return "Couldn't connect to the source. Check that the server is running and your device is on the right network."
        case .invalidResponse: return "Got an unexpected response from the server."
        case .parseFailed:     return "Couldn't read the server's response."
        case .downloadFailed:  return "Download interrupted. Try again?"
        }
    }
}

/// Thin wrapper around URLSession for OPDS feed requests and epub
/// downloads.
struct OPDSClient {

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch and parse one page of an OPDS feed.
    ///
    /// - Parameters:
    ///   - source: The source to fetch from. Used to compute the root
    ///     URL when `pageURL` is nil and to look up auth credentials.
    ///   - pageURL: When paging through results, pass the `nextPageURL`
    ///     from the previous fetch. Pass nil for the first page.
    func fetchFeed(
        from source: BookSource,
        pageURL: URL? = nil
    ) async throws -> OPDSFeedPage {

        let url: URL
        if let pageURL { url = pageURL }
        else if let root = source.feedURL { url = root }
        else { throw OPDSError.sourceUnreachable }

        let request = makeRequest(url: url, source: source)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw OPDSError.invalidResponse
            }
            guard let page = OPDSFeedParser.parse(data) else {
                throw OPDSError.parseFailed
            }
            return page
        } catch let opdsError as OPDSError {
            throw opdsError
        } catch {
            throw OPDSError.sourceUnreachable
        }
    }

    /// Download one epub from an acquisition URL into a temporary file.
    /// Caller hands the resulting URL to the IngestionPipeline.
    func downloadEpub(
        from url: URL,
        source: BookSource? = nil
    ) async throws -> URL {
        var request = URLRequest(url: url)
        if let source { applyAuthHeader(to: &request, source: source) }

        do {
            let (tempURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw OPDSError.downloadFailed
            }
            // Move into our own temp location with an .epub extension so
            // downstream code can recognise it.
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).epub")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            throw OPDSError.downloadFailed
        }
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, source: BookSource) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyAuthHeader(to: &request, source: source)
        return request
    }

    /// Add an HTTP Basic Auth header if the source needs one. The
    /// credentials lookup goes through KeychainHelper (Settings module)
    /// — TODO: wire that up once the helper exists. Until then any
    /// auth-required source will fail at the server with 401, which is
    /// surfaced as `OPDSError.invalidResponse`.
    private func applyAuthHeader(to request: inout URLRequest, source: BookSource) {
        guard source.requiresAuth else { return }
        // TODO: Look up (username, password) for source.id from Keychain.
        // let credentials = KeychainHelper.basicAuth(for: source.id)
        // request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
    }
}
