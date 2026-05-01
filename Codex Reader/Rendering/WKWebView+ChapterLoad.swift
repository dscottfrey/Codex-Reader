//
//  WKWebView+ChapterLoad.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A tiny scheme-aware load helper for chapter URLs. Bridges the two
//  paths the reader currently supports:
//
//    • file:// URLs — produced by the legacy custom EpubParser, which
//      unzips the epub into a temp directory. These need
//      `loadFileURL(_:allowingReadAccessTo:)` so WebKit grants the
//      WebView access to the unzipped tree's resources (CSS, images,
//      fonts referenced by relative paths).
//
//    • http(s):// URLs — produced by the Readium-backed `EpubLoader`,
//      which serves the epub through Readium's GCDHTTPServer. These
//      need `load(URLRequest:)`. The `readAccessURL` is meaningless for
//      HTTP transport and is ignored.
//
//  WHY A HELPER:
//  Two call sites (WKWebViewWrapper for scroll mode; ChapterPageRenderer
//  for the off-screen page baker) need the same scheme branch.
//  Centralising it here means the day we delete the EpubParser path,
//  we update one call site instead of two.
//

import Foundation
@preconcurrency import WebKit

extension WKWebView {

    /// Load a chapter at `url`, picking the right WebKit API for the
    /// URL's scheme. `readAccess` is consulted only for file URLs.
    func loadChapter(at url: URL, readAccess: URL?) {
        if url.isFileURL {
            // Legacy custom-parser path. WebKit needs explicit read
            // access to the unzipped epub root.
            loadFileURL(url, allowingReadAccessTo: readAccess ?? url.deletingLastPathComponent())
        } else {
            // Readium-served path — straightforward HTTP load.
            load(URLRequest(url: url))
        }
    }
}
