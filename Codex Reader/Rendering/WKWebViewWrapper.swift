//
//  WKWebViewWrapper.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The SwiftUI bridge to WKWebView. Wraps a WKWebView in a
//  UIViewRepresentable so the rest of the app can compose it into SwiftUI
//  layouts. Defined in Module 1 (Rendering Engine) §3.1.
//
//  WHAT LIVES HERE:
//  - The WKWebView configured with our typography user script and the
//    pagination user script (PaginationJS).
//  - A `WKScriptMessageHandler` that receives JS→Swift messages from the
//    pagination script.
//  - Chapter-URL loading: `updateUIView` watches the `fileURL` input and
//    reloads the web view when it changes. This is how chapter
//    transitions happen — the view model flips `currentChapterHref`,
//    SwiftUI hands us a new `fileURL`, and we call `loadFileURL`.
//
//  WHY NOT SwiftUI's NEW WebView:
//  As of iOS 17 there is no first-class SwiftUI web view; WKWebView is
//  the canonical Apple API and is what the directive specifies.
//
//  WHY TWO USER SCRIPTS:
//  `userScript` handles CSS injection (FOUC defence, §3.3). The
//  pagination script handles layout + JS API (§2.7 and PaginationJS).
//  Keeping them separate means a settings change only has to rebuild
//  the CSS script, not the pagination one.
//

import SwiftUI
@preconcurrency import WebKit

/// A SwiftUI-friendly wrapper around WKWebView for rendering one
/// chapter at a time.
struct WKWebViewWrapper: UIViewRepresentable {

    // MARK: - Inputs

    /// The typography user script (CSS injection). Rebuilt whenever the
    /// effective settings change so the next navigation picks up the
    /// new styles from frame zero.
    let userScript: WKUserScript

    /// The pagination user script (PaginationJS). Rebuilt when the
    /// page-turn mode flips between paginated and scroll.
    let paginationScript: WKUserScript

    /// The URL of the chapter XHTML the web view should display. When
    /// this changes, `updateUIView` triggers a reload.
    let fileURL: URL?

    /// The directory the WebView is allowed to read from — the
    /// unzipped epub root. Needed by `loadFileURL(_:allowingReadAccessTo:)`
    /// so relative CSS / image / font references resolve.
    let readAccessURL: URL?

    /// Called by `makeUIView` once with the freshly-created WKWebView so
    /// the caller can keep a reference for `evaluateJavaScript`.
    let webViewProxy: (WKWebView) -> Void

    /// Called every time a navigation finishes.
    let onDidFinish: (WKWebView) -> Void

    /// Called whenever the pagination JS posts a message (pagination
    /// report, page change, scroll progress).
    let onPaginationMessage: (PaginationMessage) -> Void

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDidFinish: onDidFinish,
            onPaginationMessage: onPaginationMessage
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // 1. Typography CSS at document start — FOUC defence (§3.3).
        config.userContentController.addUserScript(userScript)
        // 2. Pagination JS at document start — column layout in place
        //    before the chapter parses.
        config.userContentController.addUserScript(paginationScript)

        // 3. JS→Swift message handler. The JS posts to
        //    `window.webkit.messageHandlers.<name>` — names must match.
        config.userContentController.add(
            context.coordinator,
            name: PaginationJS.messageHandlerName
        )

        // Non-persistent data store — WebKit cookies / local storage /
        // service workers must never bleed across books.
        config.websiteDataStore = .nonPersistent()

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false
        web.isOpaque = true

        // Track what we've loaded so updateUIView can decide whether a
        // new fileURL means "reload" or "same as before, do nothing."
        context.coordinator.lastLoadedURL = fileURL

        webViewProxy(web)
        if let url = fileURL, let access = readAccessURL {
            web.loadFileURL(url, allowingReadAccessTo: access)
        }
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Rebuild user scripts when either script changes. We can't
        // mutate an installed WKUserScript — remove-all and re-add is
        // the supported pattern.
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(userScript)
        webView.configuration.userContentController.addUserScript(paginationScript)

        // Reload when the chapter URL actually changed. Comparing paths
        // avoids a spurious reload when SwiftUI rebuilds the
        // representable but the URL is identical.
        if let url = fileURL,
           let access = readAccessURL,
           context.coordinator.lastLoadedURL?.path != url.path {
            context.coordinator.lastLoadedURL = url
            webView.loadFileURL(url, allowingReadAccessTo: access)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // WKScriptMessageHandlers are retained by the content
        // controller. Remove ours explicitly so the coordinator can
        // deallocate cleanly.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: PaginationJS.messageHandlerName)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKScriptMessageHandler {

        private let onDidFinish: (WKWebView) -> Void
        private let onPaginationMessage: (PaginationMessage) -> Void

        /// The URL we most recently fed to `loadFileURL`. Used by
        /// `updateUIView` to tell "the chapter actually changed" apart
        /// from "SwiftUI rebuilt the view with the same URL."
        var lastLoadedURL: URL?

        init(
            onDidFinish: @escaping (WKWebView) -> Void,
            onPaginationMessage: @escaping (PaginationMessage) -> Void
        ) {
            self.onDidFinish = onDidFinish
            self.onPaginationMessage = onPaginationMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onDidFinish(webView)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let parsed = PaginationMessage(from: message.body) else { return }
            onPaginationMessage(parsed)
        }
    }
}
