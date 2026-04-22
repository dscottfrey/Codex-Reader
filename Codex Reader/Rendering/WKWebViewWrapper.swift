//
//  WKWebViewWrapper.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The SwiftUI bridge to WKWebView. Wraps a WKWebView in a
//  UIViewRepresentable so the rest of the app can compose it into SwiftUI
//  layouts. Defined in Module 1 (Rendering Engine) §3.1.
//
//  WHY UIViewRepresentable AND NOT SwiftUI's NEW WebView:
//  As of iOS 17 there is no first-class SwiftUI web view; WKWebView is
//  the canonical Apple API and is what the directive specifies. Wrapping
//  it ourselves keeps full control over user-script injection, the
//  navigation delegate, and the loadFileURL access scope.
//
//  WHY THE COORDINATOR PATTERN:
//  The Coordinator owns the navigation delegate. SwiftUI rebuilds the
//  representable on every state change, but the Coordinator persists. The
//  Coordinator carries an id-based reference to the view model so the
//  webView delegate methods can call back into Codex when a chapter
//  finishes loading (the annotation injection hook, §3.4).
//

import SwiftUI
@preconcurrency import WebKit

/// A SwiftUI-friendly wrapper around WKWebView for rendering one chapter.
///
/// The wrapper is intentionally small. Loading content is the caller's
/// job (it builds the chapter file URL and calls `loadFileURL` via the
/// `webViewProxy` callback). The wrapper handles two things:
///   1. Configuring the WKWebView with our user script (the CSS injection).
///   2. Forwarding the didFinish navigation callback so the renderer can
///      kick off annotation injection and pagination calculation.
struct WKWebViewWrapper: UIViewRepresentable {

    // MARK: - Inputs

    /// The user script to install. Built by UserScriptBuilder. When this
    /// changes between renders the user script is rebuilt — used for the
    /// "settings changed, rebuild the script" path.
    let userScript: WKUserScript

    /// Called by `makeUIView` once with the freshly-created WKWebView so
    /// the caller can keep a reference to call `loadFileURL` etc.
    let webViewProxy: (WKWebView) -> Void

    /// Called every time a navigation finishes. The renderer uses this
    /// to invoke the annotation injection hook (§3.4).
    let onDidFinish: (WKWebView) -> Void

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onDidFinish: onDidFinish)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Inject the user CSS at document start. This is the FOUC defence
        // (Rendering Engine §3.3): styles are present before the epub HTML
        // is parsed, so the cascade has the user's overrides from frame
        // zero.
        config.userContentController.addUserScript(userScript)

        // Use a non-persistent data store. We never want WebKit cookies,
        // local storage, or service workers to bleed across books.
        config.websiteDataStore = .nonPersistent()

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false  // no back/forward inside an epub chapter
        web.scrollView.bounces = false                   // pagination feels wrong with bounce
        web.isOpaque = true

        // Hand the freshly-created web view to the caller so they can
        // load content into it.
        webViewProxy(web)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Rebuild the user-script set whenever the wrapper is recreated
        // with a new userScript value. We can't mutate an installed
        // WKUserScript — we have to remove all and re-add.
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(userScript)
    }

    // MARK: - Coordinator (delegate)

    final class Coordinator: NSObject, WKNavigationDelegate {

        private let onDidFinish: (WKWebView) -> Void

        init(onDidFinish: @escaping (WKWebView) -> Void) {
            self.onDidFinish = onDidFinish
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Forward so the Rendering Engine can run its post-render
            // hooks (annotation injection, pagination calculation).
            onDidFinish(webView)
        }
    }
}
