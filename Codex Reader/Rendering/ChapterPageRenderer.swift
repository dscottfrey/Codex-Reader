//
//  ChapterPageRenderer.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The off-screen WKWebView that bakes a chapter's pages into UIImages.
//  Called by `ReaderViewModel` for each chapter the user reaches; its
//  output (UIImages) is stored in `PageImageCache` and displayed by
//  `PageImageVC` inside `PaginatedChapterView`.
//
//  WHY ONE OFF-SCREEN WebView (NOT N LIVE WebViews):
//  Per Rendering directive §3.3, the WKWebView is a *content baker*,
//  not a display surface. It renders each chapter page once into a
//  UIImage, and that image is what the reader actually shows. This
//  decoupling enables (a) Core Image post-processing for grain/warmth/
//  shadow without re-rendering, (b) page-curl animations operating on
//  cheap UIImages instead of expensive WebView snapshots, and (c) a
//  bounded WKWebView count (one renderer instance, regardless of
//  chapter length).
//
//  STATEFUL, ONE-CHAPTER-AT-A-TIME:
//  `loadChapter(...)` opens a chapter URL into the off-screen WebView,
//  waits for layout to settle, and returns the page count. Subsequent
//  `snapshot(pageIndex:)` calls each render one column of that
//  chapter. To switch to a different chapter (cross-chapter pre-render,
//  forward navigation), call `loadChapter` again — the WebView is
//  reused. The orchestrator (ReaderViewModel) decides what order to
//  bake pages in.
//
//  WHY THE WebView IS RECREATED ON VIEWPORT CHANGE:
//  CSS Columns reads `window.innerWidth` to size each column. If the
//  WKWebView is initialised at one frame and then resized, innerWidth
//  doesn't reliably update — the column geometry from the original
//  size persists, producing stale snapshots. Recreating the WebView
//  with the new frame size forces a fresh innerWidth and clean column
//  layout. The cost is one extra navigation per rotation; small
//  compared to the cost of stale renders.
//I don't think we can d
//  TIMING — WHY THE TINY ASYNC SLEEPS:
//  After `didFinish` and after `codexSnapToPage`, layout/transform
//  apply asynchronously through the browser's render loop. We yield
//  one frame's worth of time (~16ms) so scrollWidth and the column
//  transform are stable before we read them. These sleeps are the
//  least-bad option without subscribing to the JS message bridge,
//  which is a heavier integration than this milestone needs.
//

import Foundation
import UIKit
@preconcurrency import WebKit

@MainActor
final class ChapterPageRenderer: NSObject {

    // MARK: - Errors

    enum RenderError: LocalizedError {
        case noWebView
        case loadFailed(Error)
        case snapshotFailed(Error?)
        case javaScriptFailed(Error?)
        case pageCountUnreadable
        case pageIndexOutOfRange(requested: Int, total: Int)

        var errorDescription: String? {
            switch self {
            case .noWebView:                            return "Renderer has no WebView."
            case .loadFailed(let e):                    return "Chapter load failed: \(e.localizedDescription)"
            case .snapshotFailed(let e):                return "Snapshot failed: \(e?.localizedDescription ?? "unknown")"
            case .javaScriptFailed(let e):              return "JavaScript failed: \(e?.localizedDescription ?? "unknown")"
            case .pageCountUnreadable:                  return "Couldn't read chapter page count."
            case .pageIndexOutOfRange(let r, let t):    return "Page \(r) is out of range (chapter has \(t))."
            }
        }
    }

    // MARK: - State

    private var webView: WKWebView?
    private var currentViewportSize: CGSize = .zero

    /// Continuation resumed by the navigation delegate when the chapter
    /// finishes loading (or fails). Set by `loadChapter` and consumed
    /// by `webView(_:didFinish:)` / didFail variants.
    private var loadContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Public API

    /// Load `url` into the off-screen WebView and return the chapter's
    /// page count. After this returns, `snapshot(pageIndex:)` may be
    /// called repeatedly for any page in `1...pageCount`.
    ///
    /// - Parameters:
    ///   - url: chapter URL (Readium-served localhost or legacy file URL).
    ///   - viewportSize: the on-screen reading-area size. The off-screen
    ///     WebView is sized to match so column geometry lines up with
    ///     what the user will see.
    ///   - userScript: the typography CSS user script (from
    ///     `UserScriptBuilder.makeUserScript(css:)`).
    ///   - paginationScript: the pagination JS user script (from
    ///     `UserScriptBuilder.makePaginationScript(paginated:)`),
    ///     paginated mode only — Scroll mode doesn't go through here.
    func loadChapter(
        url: URL,
        viewportSize: CGSize,
        userScript: WKUserScript,
        paginationScript: WKUserScript
    ) async throws -> Int {

        // Recreate the WebView on first use or whenever the viewport
        // changes (see file header for why we don't try to resize).
        if webView == nil || currentViewportSize != viewportSize {
            webView = makeOffscreenWebView(
                viewportSize: viewportSize,
                userScript: userScript,
                paginationScript: paginationScript
            )
            currentViewportSize = viewportSize
        } else {
            // Same viewport, fresh chapter — reinstall scripts so any
            // typography change since the last load is reflected in
            // the new chapter's render.
            let cc = webView!.configuration.userContentController
            cc.removeAllUserScripts()
            cc.addUserScript(userScript)
            cc.addUserScript(paginationScript)
        }

        guard let webView else { throw RenderError.noWebView }

        // If a previous load was still suspended on its continuation
        // (orchestrator cancelled the parent task before didFinish
        // fired), resume it now with a cancellation error so the old
        // task can return cleanly. Without this, the continuation
        // would leak when we overwrite it below.
        if let stale = loadContinuation {
            loadContinuation = nil
            stale.resume(throwing: CancellationError())
        }

        // Load and wait for didFinish.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            webView.loadChapter(at: url, readAccess: nil)
        }

        // Two frames' tick lets CSS Columns layout settle. PaginationJS
        // runs its initial measure() inside requestAnimationFrame at
        // frame 1 of the page load, but for long chapters layout isn't
        // done by then; the JS-side `totalPages` ends up at 1 even
        // though scrollWidth has the right value once layout finishes.
        // We sleep here so layout is stable, then call codexMeasure()
        // below to refresh both Swift's count and JS's closure variable.
        try? await Task.sleep(nanoseconds: 32_000_000)   // ~2 frames at 60fps

        // Force a fresh measure on the JS side and read its result.
        // codexMeasure() updates the closure-scoped `totalPages` AND
        // returns it, so subsequent codexSnapToPage(n) calls won't
        // trip the out-of-range guard for valid pages — that bug
        // produced "every page after the first is blank" because the
        // guard hides the body and returns without setting transform.
        let raw = try await runJS("window.codexMeasure();")
        guard let count = (raw as? NSNumber)?.intValue, count >= 1 else {
            throw RenderError.pageCountUnreadable
        }
        return count
    }

    /// Render page `pageIndex` (1-based) of the currently-loaded
    /// chapter to a UIImage. Caller must ensure `loadChapter` has
    /// completed and the index is in range.
    func snapshot(pageIndex: Int, totalPages: Int) async throws -> UIImage {
        guard let webView else { throw RenderError.noWebView }
        guard pageIndex >= 1 && pageIndex <= totalPages else {
            throw RenderError.pageIndexOutOfRange(requested: pageIndex, total: totalPages)
        }

        // Silent jump (no pageChanged event) — we're rendering, not
        // navigating.
        _ = try await runJS("window.codexSnapToPage(\(pageIndex));")

        // Let the translateX commit before snapshotting. One frame is
        // sufficient — the translate is purely visual, no layout.
        try? await Task.sleep(nanoseconds: 16_000_000)

        #if DEBUG
        // Diagnostic — verify codexSnapToPage actually moved the body.
        // If transform stays at translateX(0px) for every pageIndex,
        // every snapshot is page 1 content (this is the §2.1.C-style
        // "every page shows page 1" symptom).
        if let transformAny = try? await runJS("document.body.style.transform || '';"),
           let transform = transformAny as? String {
            NSLog("[Codex Render] snapshot pageIndex=\(pageIndex)/\(totalPages) transform=\"\(transform)\"")
        }
        #endif

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: currentViewportSize)
        let image: UIImage = try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: config) { image, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: RenderError.snapshotFailed(error))
                }
            }
        }

        #if DEBUG
        // Quick image-content fingerprint — if two pageIndex snapshots
        // have the same fingerprint, the takeSnapshot call captured the
        // same pixels for both, and the CSS transform didn't take
        // visual effect even though it's set in the DOM.
        if let png = image.pngData() {
            NSLog("[Codex Render] snapshot pageIndex=\(pageIndex) bytes=\(png.count) head=\(png.prefix(16).map { String(format: "%02x", $0) }.joined())")
        }
        #endif

        return image
    }

    /// Drop the off-screen WebView. Called on book close to free the
    /// WebKit process resources.
    func tearDown() {
        // If a load was suspended waiting on didFinish, resume it
        // with a cancellation error so its parent task can return
        // instead of leaking.
        if let cont = loadContinuation {
            loadContinuation = nil
            cont.resume(throwing: CancellationError())
        }
        webView?.stopLoading()
        webView = nil
        currentViewportSize = .zero
    }

    // MARK: - Internals

    private func makeOffscreenWebView(
        viewportSize: CGSize,
        userScript: WKUserScript,
        paginationScript: WKUserScript
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(userScript)
        config.userContentController.addUserScript(paginationScript)
        // Non-persistent — same as the live WebViews. Cookies / local
        // storage / service workers must not persist between books.
        config.websiteDataStore = .nonPersistent()

        let frame = CGRect(origin: .zero, size: viewportSize)
        let web = WKWebView(frame: frame, configuration: config)
        web.navigationDelegate = self
        web.isOpaque = true
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false
        // Deliberately not added to a view hierarchy. Per directive
        // §3.3 the off-screen WebView lives outside any window. The
        // off-screen-rendering scale issue is compensated for by the
        // CSS font-size scale factor applied upstream in ReaderViewModel
        // (search for `OFF_SCREEN_RENDER_SCALE`).
        return web
    }

    private func runJS(_ source: String) async throws -> Any? {
        guard let webView else { throw RenderError.noWebView }
        return try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(source) { result, error in
                if let error {
                    cont.resume(throwing: RenderError.javaScriptFailed(error))
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension ChapterPageRenderer: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            loadContinuation?.resume()
            loadContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if Self.isCancellationFromOldNavigation(error) { return }
        Task { @MainActor in
            loadContinuation?.resume(throwing: RenderError.loadFailed(error))
            loadContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if Self.isCancellationFromOldNavigation(error) { return }
        Task { @MainActor in
            loadContinuation?.resume(throwing: RenderError.loadFailed(error))
            loadContinuation = nil
        }
    }

    /// True when the delegate is reporting that an old navigation was
    /// cancelled because we started a new one. We already handle the
    /// orchestration side of that — the in-flight `loadContinuation`
    /// was resumed manually with `CancellationError` at the top of
    /// `loadChapter` — so the delegate's -999 callback is a redundant
    /// signal for an event we've already handled. Without this guard
    /// the delegate would resume the *new* load's continuation with
    /// a stale -999 error, making the new load appear to fail
    /// immediately. This is the root cause of the
    /// "settings slider produces NSURLErrorCancelled" bug.
    private nonisolated static func isCancellationFromOldNavigation(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
