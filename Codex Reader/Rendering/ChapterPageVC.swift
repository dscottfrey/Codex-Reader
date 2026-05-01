//
//  ChapterPageVC.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A UIViewController that shows ONE page of an epub chapter. Owns its
//  own WKWebView, loads the chapter, and after the pagination JS
//  measures the chapter's column count, jumps to its assigned page
//  index and stays there. It never changes pages — a neighbouring page
//  is a neighbouring view controller.
//
//  WHY ONE VC PER PAGE:
//  `UIPageViewController(.pageCurl)` and (.scroll) take snapshots of
//  the visible view controllers during their transition animations.
//  For the curl to show the right content on both sides of the curl,
//  each page must be its own VC with its own view hierarchy. See
//  memory `project_page_curl_deal_breaker` for the architectural
//  rationale.
//
//  WHY NOT ONE WKWebView FOR THE WHOLE CHAPTER:
//  That's how the earlier CSS-transform Slide worked. Sharing a
//  WKWebView across multiple page VCs means only one page can display
//  at a time, which breaks the curl/slide transitions that need both
//  adjacent pages rendered simultaneously.
//
//  MEMORY BUDGET:
//  UIPageViewController keeps ~3 page VCs alive (current, prev, next)
//  and releases the rest, so the "N WebViews per chapter" concern is
//  not real — effective memory is ~3 WebViews per open chapter, which
//  matches Rendering §5's budget.
//

import UIKit
@preconcurrency import WebKit

/// Hosts one WKWebView displaying a single page of a chapter.
///
/// Lifecycle:
///   1. `init` captures chapter URL, page index, and the shared scripts.
///   2. `loadView` builds a WKWebView with those scripts installed.
///   3. `viewDidLoad` calls `loadFileURL` to render the chapter.
///   4. When the PaginationJS inside the web view reports pagination,
///      the coordinator on the parent PaginatedChapterView calls
///      `snapToAssignedPage()` on this VC so the web view jumps to
///      the correct column.
final class ChapterPageVC: UIViewController {

    // MARK: - Inputs (immutable for the VC's lifetime)

    /// The chapter file URL this VC is displaying. A chapter change
    /// creates fresh VCs — this value never mutates.
    let chapterURL: URL

    /// Directory the web view is allowed to read from.
    let readAccessURL: URL

    /// Which page of the chapter this VC shows (1-based). The web view
    /// snaps here after the pagination JS measures.
    let pageIndex: Int

    /// The typography and pagination user scripts installed on the
    /// web view at document-start time.
    private let userScript: WKUserScript
    private let paginationScript: WKUserScript

    /// Routed message handler — posts every pagination message up to
    /// the coordinator, which decides whether to act on it.
    private weak var messageHandler: WKScriptMessageHandler?

    // MARK: - The web view

    /// The WebView is created in `loadView` (when UIKit first asks
    /// for the VC's view). It stays nil until then — a VC that the
    /// data source built but UIKit hasn't displayed yet has no view.
    /// Callers iterating the live-VC registry must tolerate nil.
    private(set) var webView: WKWebView?

    /// Becomes true once the pagination JS has reported its first
    /// measurement AND we've snapped to our assigned page. Used to
    /// guard re-entry into `snapToAssignedPage` on live settings
    /// changes (the JS re-measures on resize — we want the snap to
    /// repeat then, so this is reset externally).
    var hasSnappedToPage: Bool = false

    // MARK: - Init

    init(
        chapterURL: URL,
        readAccessURL: URL,
        pageIndex: Int,
        userScript: WKUserScript,
        paginationScript: WKUserScript,
        messageHandler: WKScriptMessageHandler
    ) {
        self.chapterURL = chapterURL
        self.readAccessURL = readAccessURL
        self.pageIndex = pageIndex
        self.userScript = userScript
        self.paginationScript = paginationScript
        self.messageHandler = messageHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ChapterPageVC is created programmatically only.")
    }

    // MARK: - View setup

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(userScript)
        config.userContentController.addUserScript(paginationScript)
        if let handler = messageHandler {
            config.userContentController.add(
                handler,
                name: PaginationJS.messageHandlerName
            )
        }
        // Non-persistent so cookies/local-storage never leak across
        // books. Matches WKWebViewWrapper's scroll-mode path.
        config.websiteDataStore = .nonPersistent()

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.bounces = false
        // The page curl animation needs the background to be stable;
        // transparent webviews produce visible artifacts in the curl.
        web.isOpaque = true
        web.allowsBackForwardNavigationGestures = false

        self.webView = web
        self.view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView?.loadChapter(at: chapterURL, readAccess: readAccessURL)
    }

    // MARK: - Commands from the coordinator

    /// Jump the web view to this VC's assigned page without firing a
    /// `pageChanged` message (this is setup, not a user turn — the
    /// `codexSnapToPage` function in PaginationJS is the silent
    /// variant). Safe to call multiple times.
    func snapToAssignedPage() {
        let js = "window.codexSnapToPage && window.codexSnapToPage(\(pageIndex));"
        #if DEBUG
        // Diagnostic: each page VC logs when it's told to lock to
        // its assigned column. If two VCs in a spread end up showing
        // identical content, comparing their snap log lines (page
        // index, WebView object id) in the Xcode console tells us
        // whether the snap landed on the right VC.
        NSLog("[Codex] snapToAssignedPage pageIndex=\(pageIndex) webView=\(ObjectIdentifier(webView ?? WKWebView()).hashValue)")
        #endif
        webView?.evaluateJavaScript(js, completionHandler: { _, err in
            #if DEBUG
            if let err = err {
                NSLog("[Codex] codexSnapToPage(\(self.pageIndex)) error: \(err)")
            }
            #endif
        })
        hasSnappedToPage = true
    }

    /// Tear down the JS message-handler registration at dealloc time.
    /// The content controller retains handlers strongly — not doing
    /// this would leak the coordinator across chapter changes.
    deinit {
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: PaginationJS.messageHandlerName)
    }
}
