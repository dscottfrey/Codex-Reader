//
//  ReaderViewModel.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Observable state for the reader. Holds the open book, the
//  current chapter, chrome state, the pagination engine, and the
//  effective settings. The ReaderView observes this and rebuilds
//  when it changes.
//
//  WHY A SEPARATE FILE:
//  Per the §6.3 rule "views don't contain business logic", the
//  reader's state and the chapter-loading / page-turning logic do
//  not live inside ReaderView.swift. ReaderView is presentation only.
//

import Foundation
import SwiftData
import SwiftUI
@preconcurrency import WebKit

@MainActor
@Observable
final class ReaderViewModel {

    // MARK: - Inputs

    /// The book currently being read.
    let book: Book

    /// The user's global settings, captured at open time and refreshed
    /// whenever Settings changes them.
    var globalSettings: ReaderSettings

    // MARK: - State

    /// True while the title/metadata strips (System 1 chrome) are visible.
    var chromeVisible: Bool = false

    /// True when the floating options panel (System 2) is open.
    var optionsPanelOpen: Bool = false

    /// True while the reader settings (Aa) bottom sheet is open.
    var settingsPanelOpen: Bool = false

    /// True the very first time this book is opened, when the typography
    /// prompt (§4.6) needs to appear before the first chapter is shown.
    var typographyPromptShown: Bool = false

    /// Currently-loaded chapter href. nil while the parser is still
    /// figuring out where to start.
    var currentChapterHref: String?

    /// The parsed epub — populated once `loadBook()` completes.
    var parsed: ParsedEpub?

    /// User-visible error, if loading or parsing failed.
    var loadError: String?

    /// Pagination state — reset on chapter change, updated by the
    /// PaginationJS bridge.
    let pagination = PaginationEngine()

    /// When a chapter transition was triggered by a "previous page"
    /// gesture we want to land on the new chapter's last page, not its
    /// first. This flag is read after the chapter finishes loading and
    /// the JS reports its page count, then cleared.
    var pendingJumpToLastPage: Bool = false

    /// The Readium-backed loader for this reading session. Holds the
    /// HTTP server that serves the epub's resources to the WKWebView.
    /// Recreated per book; closed on book dismissal so the server is
    /// stopped. See EpubLoader.swift for the architecture.
    private let loader = EpubLoader()

    /// LRU cache of pre-rendered page UIImages for paginated modes.
    /// Read by `PaginatedChapterView` when it builds a `PageImageVC`;
    /// written by `renderCurrentChapter(viewportSize:)` as the renderer
    /// finishes each page. See PageImageCache.swift for the capacity
    /// rationale.
    let pageImageCache = PageImageCache()

    /// The off-screen WKWebView that bakes chapter pages into UIImages.
    /// One instance for the life of the reading session; reused across
    /// chapters. See ChapterPageRenderer.swift.
    private let pageRenderer = ChapterPageRenderer()

    /// In-flight render task for the current chapter. Cancelled on
    /// chapter change so a partially-rendered old chapter doesn't
    /// continue baking pages no one needs.
    private var renderTask: Task<Void, Never>?

    /// The viewport size we last rendered against. Used to detect
    /// rotation / split-view changes that invalidate column geometry
    /// and require a full cache flush.
    private var lastRenderedViewport: CGSize = .zero

    // MARK: - Init

    init(book: Book, globalSettings: ReaderSettings) {
        self.book = book
        self.globalSettings = globalSettings
    }

    // MARK: - Effective settings & CSS

    var effective: ReaderSettings? {
        effectiveSettings(global: globalSettings, book: book)
    }

    var theme: ReaderTheme {
        effectiveTheme(global: globalSettings, book: book)
    }

    func currentCSS(publisherSafetyFloorPt: CGFloat = 10) -> String {
        CSSBuilder.build(
            effective: effective,
            theme: theme,
            publisherSafetyFloorPt: publisherSafetyFloorPt
        )
    }

    /// The effective page-turn style for this book.
    var effectivePageTurnStyle: PageTurnStyle {
        effective?.pageTurnStyle ?? globalSettings.pageTurnStyle
    }

    /// True while we want the JS to lay the chapter out as columns.
    /// False for Scroll mode.
    var paginatedMode: Bool {
        effectivePageTurnStyle != .scroll
    }

    /// Translate the surface's `GeometryReader.size` into the per-page
    /// slot size the off-screen renderer should bake to.
    ///
    /// In single-page modes (iPhone, iPad portrait, Slide) the slot is
    /// the full reading area and we pass through. In iPad landscape
    /// Page Curl the surface displays a two-page spread, so each slot
    /// is HALF the width. Rendering at full width and then aspect-fit-
    /// scaling into a half-width slot would halve the visible type
    /// size — which is exactly the "tiny type on a portrait page"
    /// regression. Halving the width here keeps column geometry and
    /// font size consistent with what the user expects.
    func effectiveViewportSize(geometryReaderSize: CGSize) -> CGSize {
        let isLandscape = geometryReaderSize.width > geometryReaderSize.height
        let isIPad      = UIDevice.current.userInterfaceIdiom == .pad
        let isCurl      = effectivePageTurnStyle == .curl
        let isSpread    = isCurl && isIPad && isLandscape
        if isSpread {
            return CGSize(
                width: geometryReaderSize.width / 2,
                height: geometryReaderSize.height
            )
        }
        return geometryReaderSize
    }

    // MARK: - Lifecycle

    /// Open the epub via the Readium-backed loader and pick a starting
    /// chapter. The loader starts a local HTTP server that serves the
    /// epub's resources to WKWebView for the life of the reading
    /// session — `closeBook()` tears it down.
    func loadBook() async {
        guard let fileURL = currentEpubURL() else {
            loadError = "Couldn't find this book's file."
            return
        }

        do {
            let parsed = try await loader.open(fileURL)
            self.parsed = parsed

            // Pick the chapter to land on: saved position, or first linear.
            let startHref =
                book.lastChapterHref
                ?? parsed.spine.first(where: { $0.linear })?.href
                ?? parsed.spine.first?.href
            self.currentChapterHref = startHref

            // Prime the pagination engine with the spine index so
            // book-level progress can be computed from the first tick.
            pagination.willLoadChapter(
                spineIndex: PageNavigator.spineIndex(of: startHref, in: parsed.spine) ?? 0,
                spineCount: parsed.spine.count
            )

            // First-open typography prompt is intentionally not shown.
            // Default mode is My Defaults (`.userDefaults`); the user
            // can switch to Publisher or Custom from the Aa settings
            // panel at any time.
        } catch let loaderError as EpubLoaderError {
            loadError = loaderError.errorDescription ?? "Couldn't open this book."
        } catch {
            loadError = "Couldn't open this book: \(error.localizedDescription)"
        }
    }

    /// Stop the local HTTP server and release the publication. Call
    /// when the reader dismisses the book — leaving the server running
    /// after the user closes a book wastes resources.
    func closeBook() {
        renderTask?.cancel()
        renderTask = nil
        pageImageCache.clear()
        pageRenderer.tearDown()
        loader.close()
    }

    // MARK: - Page render orchestration (paginated modes only)

    /// Kick off rendering of the current chapter into the page image
    /// cache, sized to `viewportSize`. Called by `ReaderView+Surfaces`
    /// on initial appearance, on chapter change, on viewport size
    /// change (rotation, split view), and after typography settings
    /// change. Cancels any in-flight render.
    ///
    /// Render priority:
    ///   1. Land page (current page or last page if pendingJumpToLastPage)
    ///   2. Adjacent pages, fanning outward (N+1, N-1, N+2, N-2, …)
    ///   3. First page (or first 2 for spread mode) of the *next*
    ///      chapter — the cross-chapter pre-render. More important
    ///      than caching deeper into the current chapter because
    ///      sequential readers cross the boundary; nobody pages 10
    ///      ahead in one chapter.
    ///
    /// On viewport change every cached image becomes stale (column
    /// geometry differs); the cache is flushed before re-rendering.
    func renderCurrentChapter(viewportSize: CGSize) {
        // Cancel any in-flight render — its outputs target whatever
        // chapter / viewport / typography combo was current when it
        // was started, which may no longer match.
        renderTask?.cancel()

        guard let parsed = self.parsed,
              let href = self.currentChapterHref,
              let spineItem = parsed.spine.first(where: { $0.href == href }),
              viewportSize.width > 0, viewportSize.height > 0
        else { return }

        // Viewport changed → every cached snapshot is stale (column
        // geometry differs). Flush wholesale; cheaper than figuring
        // out which entries match the new viewport.
        if viewportSize != lastRenderedViewport {
            pageImageCache.clear()
            lastRenderedViewport = viewportSize
        }

        let chapterURL  = spineItem.absoluteURL
        let chapterHref = href
        let css         = currentCSS()
        let userScript       = UserScriptBuilder.makeUserScript(css: css)
        let paginationScript = UserScriptBuilder.makePaginationScript(paginated: true)

        // Spine context for the cross-chapter pre-render below.
        let spineIndex = parsed.spine.firstIndex(where: { $0.href == href }) ?? 0
        let nextSpineItem: ParsedEpub.SpineItem? = (spineIndex + 1) < parsed.spine.count
            ? parsed.spine[spineIndex + 1]
            : nil

        // Capture the "land on last page" intent before launching the
        // task — the flag is single-shot and is reset here so a later
        // re-render (e.g. from a typography change) doesn't accidentally
        // jump to the chapter end again.
        let landOnLastPage = pendingJumpToLastPage
        pendingJumpToLastPage = false

        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // STEP 1 — load chapter and measure pageCount.
                let totalPages = try await self.pageRenderer.loadChapter(
                    url: chapterURL,
                    viewportSize: viewportSize,
                    userScript: userScript,
                    paginationScript: paginationScript
                )
                if Task.isCancelled { return }

                // Feed pageCount into the pagination engine so the
                // metadata strip and tap-zone navigation see the new
                // totals immediately, before any page has rendered.
                let initialPage = landOnLastPage ? totalPages : 1
                self.pagination.reportPagination(
                    total: totalPages,
                    current: initialPage,
                    paginated: true
                )

                // STEP 2 — render priority pages of current chapter.
                for pageIndex in self.priorityPageOrder(
                    initial: initialPage,
                    total: totalPages
                ) {
                    if Task.isCancelled { return }
                    if self.pageImageCache.image(
                        forChapter: chapterHref,
                        page: pageIndex
                    ) != nil { continue }
                    let image = try await self.pageRenderer.snapshot(
                        pageIndex: pageIndex,
                        totalPages: totalPages
                    )
                    if Task.isCancelled { return }
                    self.pageImageCache.setImage(
                        image,
                        forChapter: chapterHref,
                        page: pageIndex
                    )
                    self.postPageRendered(
                        chapterHref: chapterHref,
                        pageIndex: pageIndex
                    )
                }

                // STEP 3 — cross-chapter pre-render. Loads the next
                // chapter into the renderer (which displaces this
                // chapter's WebView state, but the UIImages are already
                // safely in the cache). For iPad-landscape spread mode
                // we pre-render the first 2 pages so the open-book
                // spread that begins chapter B is ready to display.
                if let next = nextSpineItem, !Task.isCancelled {
                    let nextHref = next.href
                    let nextTotal = try await self.pageRenderer.loadChapter(
                        url: next.absoluteURL,
                        viewportSize: viewportSize,
                        userScript: userScript,
                        paginationScript: paginationScript
                    )
                    let pagesToBake = self.pagination.visiblePages == 2 ? 2 : 1
                    for i in 1...min(pagesToBake, nextTotal) {
                        if Task.isCancelled { return }
                        if self.pageImageCache.image(
                            forChapter: nextHref,
                            page: i
                        ) != nil { continue }
                        let image = try await self.pageRenderer.snapshot(
                            pageIndex: i,
                            totalPages: nextTotal
                        )
                        if Task.isCancelled { return }
                        self.pageImageCache.setImage(
                            image,
                            forChapter: nextHref,
                            page: i
                        )
                        self.postPageRendered(
                            chapterHref: nextHref,
                            pageIndex: i
                        )
                    }
                }
            } catch is CancellationError {
                // Caller cancelled; no-op.
            } catch {
                #if DEBUG
                NSLog("[Codex] renderCurrentChapter failed: \(error)")
                #endif
            }
        }
    }

    /// Build the priority order for rendering: current page first,
    /// then alternating forward/backward.
    private func priorityPageOrder(initial: Int, total: Int) -> [Int] {
        guard total >= 1 else { return [] }
        var pages: [Int] = [max(1, min(initial, total))]
        var offset = 1
        while pages.count < total {
            let forward  = initial + offset
            let backward = initial - offset
            if forward  <= total { pages.append(forward) }
            if backward >= 1     { pages.append(backward) }
            offset += 1
        }
        return pages
    }

    /// Notify observers (PaginatedChapterView coordinator) that a
    /// page image has landed in the cache, so any visible PageImageVC
    /// for that chapter+pageIndex can refresh its image.
    private func postPageRendered(chapterHref: String, pageIndex: Int) {
        NotificationCenter.default.post(
            name: .codexPageRendered,
            object: nil,
            userInfo: [
                CodexNotificationKey.chapterHref: chapterHref,
                CodexNotificationKey.pageIndex: pageIndex
            ]
        )
    }

    /// Invalidate all cached images for the current chapter and
    /// re-render with the latest CSS / settings, using the viewport
    /// size of the most recent render. Call after typography changes
    /// (the user adjusted font size, margins, etc.) so the next page
    /// turn shows freshly-rendered content rather than a stale
    /// pre-render. No-op if no render has happened yet — there's
    /// nothing to invalidate, and a render will be kicked off the
    /// normal way (chapter onAppear / onChange) once a viewport size
    /// is available.
    func invalidateCurrentChapterAndRerender() {
        guard let href = currentChapterHref,
              lastRenderedViewport.width  > 0,
              lastRenderedViewport.height > 0
        else { return }
        pageImageCache.invalidate(chapterHref: href)
        renderCurrentChapter(viewportSize: lastRenderedViewport)
    }

    /// Resolve the URL on disk for the book's epub file.
    /// TODO: integrate with the iCloud module to trigger downloads when
    /// the file is cloud-only.
    private func currentEpubURL() -> URL? {
        switch book.storageLocation {
        case .iCloudDrive:
            guard let rel = book.iCloudDrivePath else { return nil }
            return URL(fileURLWithPath: rel)
        case .localOnly:
            guard let rel = book.localFallbackPath else { return nil }
            return URL(fileURLWithPath: rel)
        }
    }

    // MARK: - JS bridge integration

    /// Route a message from the PaginationJS bridge into the engine,
    /// then persist the resulting position.
    func handlePaginationMessage(_ message: PaginationMessage) {
        switch message {
        case .pagination(let total, let current, let paginated):
            pagination.reportPagination(
                total: total,
                current: current,
                paginated: paginated
            )
        case .pageChanged(let current):
            pagination.reportPageChanged(to: current)
        case .scrollProgress(let progress):
            pagination.reportScrollProgress(progress)
        }
        savePositionDebounced()
    }

    // MARK: - Chrome interactions

    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            chromeVisible.toggle()
        }
    }

    // MARK: - Position persistence

    /// Debounce window for position saves. Firing SwiftData saves on
    /// every scroll tick would thrash the context; a short debounce
    /// keeps the latest-valid position on disk within ~1 second of
    /// idle.
    private var saveTask: Task<Void, Never>?

    /// Schedule a save of the current position. Coalesces back-to-back
    /// calls (e.g. during a fast Slide scroll) into one SwiftData
    /// write.
    func savePositionDebounced() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.savePositionNow()
        }
    }

    /// Write the current chapter + progress onto the Book. SwiftData
    /// will pick it up on the next context save; we don't force-save
    /// here because the context lives at app scope.
    func savePositionNow() async {
        guard let href = currentChapterHref else { return }
        book.lastChapterHref = href
        book.lastScrollOffset = pagination.chapterProgress
        book.lastReadDate = Date()
        book.readingProgress = pagination.bookProgress
    }
}
