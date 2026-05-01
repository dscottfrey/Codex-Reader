//
//  ReaderView+Surfaces.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The reading-surface builders and tap-zone logic for ReaderView.
//  Lives in a sibling file so ReaderView.swift can stay under the
//  §6.3 ~200-line guideline and focus on the overall view-assembly
//  (chrome, bookmark ribbon, overlays, sheets).
//
//  WHAT LIVES HERE:
//  - The two reading-surface branches: paginated (Curl/Slide) vs
//    scroll.
//  - Tap-zone handlers that ask `PageNavigator` what a tap should do
//    and then either call the paginated coordinator's `turnPage`,
//    smoothly scroll the WKWebView, or trigger a chapter swap.
//

import SwiftUI
import SwiftData
import UIKit
@preconcurrency import WebKit

extension ReaderView {

    // MARK: - Reading surface selection

    @ViewBuilder
    var paginatedSurface: some View {
        if viewModel.parsed != nil,
           let chapterHref = viewModel.currentChapterHref {
            // GeometryReader is the source of truth for viewport size.
            // Reading it here lets the off-screen renderer's WKWebView
            // be sized to match what the user will see — CSS Columns
            // geometry only lines up if both viewports agree.
            GeometryReader { geo in
                PaginatedChapterView(
                    chapterHref: chapterHref,
                    transitionStyle: transitionStyle(),
                    // When the surface rebuilds mid-session (e.g. user
                    // switches page-turn style in settings), keep the
                    // reader on whatever page the pagination engine
                    // last reported. Fresh chapter loads start at 1
                    // via willLoadChapter() resetting the engine.
                    initialPageIndex: max(1, viewModel.pagination.currentPage),
                    totalPages: max(1, viewModel.pagination.totalPages),
                    pageImageCache: viewModel.pageImageCache,
                    onPageChanged: { page in
                        viewModel.pagination.reportPageChanged(to: page)
                        viewModel.savePositionDebounced()
                    },
                    onControllerReady: { coord in
                        // DEFER: `onControllerReady` fires synchronously
                        // inside `makeUIViewController`, which is part
                        // of SwiftUI's current view-update cycle.
                        // Writing to `@State` during an update produces
                        // "Modifying state during view update" — hop
                        // to the next runloop tick.
                        DispatchQueue.main.async {
                            self.paginatedCoord = coord
                        }
                    },
                    onVisiblePagesChanged: { count in
                        // Defer for the same reason — this is called
                        // from inside `spineLocationFor:`, which UIKit
                        // invokes during layout within a SwiftUI
                        // update pass.
                        DispatchQueue.main.async {
                            viewModel.pagination.reportVisiblePages(count)
                        }
                    }
                )
                // Rebuild on chapter change AND on transition-style
                // change. UIPageViewController.transitionStyle is
                // fixed at init — switching between Curl and Slide
                // requires a fresh PVC, which this `.id` forces.
                .id("\(chapterHref)|\(transitionStyle().rawValue)")
                // Kick off the off-screen render whenever the chapter
                // changes or the viewport changes (rotation, split
                // view). The renderer cancels any in-flight render
                // and starts fresh with the new inputs. See
                // ReaderViewModel.renderCurrentChapter for the
                // priority order (current page, then adjacent, then
                // next chapter's first page).
                .onAppear {
                    viewModel.renderCurrentChapter(
                        viewportSize: viewModel.effectiveViewportSize(
                            geometryReaderSize: geo.size
                        )
                    )
                }
                .onChange(of: chapterHref) { _, _ in
                    viewModel.renderCurrentChapter(
                        viewportSize: viewModel.effectiveViewportSize(
                            geometryReaderSize: geo.size
                        )
                    )
                }
                .onChange(of: geo.size) { _, newSize in
                    viewModel.renderCurrentChapter(
                        viewportSize: viewModel.effectiveViewportSize(
                            geometryReaderSize: newSize
                        )
                    )
                }
            }
            .background(viewModel.theme.backgroundColor)
        } else {
            viewModel.theme.backgroundColor
        }
    }

    @ViewBuilder
    var scrollSurface: some View {
        WKWebViewWrapper(
            userScript: UserScriptBuilder.makeUserScript(css: viewModel.currentCSS()),
            paginationScript: UserScriptBuilder.makePaginationScript(paginated: false),
            fileURL: currentChapterURL(),
            readAccessURL: viewModel.parsed?.unzippedRoot,
            webViewProxy: { web in self.scrollWebView = web },
            onDidFinish: { web in
                if let href = viewModel.currentChapterHref {
                    let store = AnnotationStore(context: modelContext)
                    let injector = AnnotationInjector(store: store)
                    injector.injectAnnotations(
                        forBookID: viewModel.book.id,
                        chapterHref: href,
                        into: web
                    )
                }
            },
            onPaginationMessage: { viewModel.handlePaginationMessage($0) }
        )
        .background(viewModel.theme.backgroundColor)
    }

    // MARK: - Tap handlers

    func handleNextPageTap() {
        guard let spine = viewModel.parsed?.spine else { return }
        let intent = PageNavigator.nextPageIntent(
            pagination: viewModel.pagination,
            spine: spine,
            currentHref: viewModel.currentChapterHref
        )
        apply(intent)
    }

    func handlePrevPageTap() {
        guard let spine = viewModel.parsed?.spine else { return }
        let intent = PageNavigator.prevPageIntent(
            pagination: viewModel.pagination,
            spine: spine,
            currentHref: viewModel.currentChapterHref
        )
        apply(intent)
    }

    private func apply(_ intent: PageIntent) {
        switch intent {
        case .turnWithinChapter(let dir):
            if viewModel.paginatedMode {
                paginatedCoord?.turnPage(
                    direction: dir == .forward ? .forward : .reverse
                )
            } else if let web = scrollWebView {
                let delta = dir == .forward ? "window.innerHeight" : "-window.innerHeight"
                web.evaluateJavaScript(
                    "window.scrollBy({ top: \(delta), left: 0, behavior: 'smooth' });",
                    completionHandler: nil
                )
            }

        case .crossToNextChapter(let href):
            swapChapter(to: href, jumpToLastPage: false)

        case .crossToPrevChapter(let href):
            // TODO: landing on the last page of the previous chapter
            // requires waiting for the new chapter's PaginationJS to
            // measure before we know the last page index. Currently
            // lands on page 1 — a known UX regression tracked as a
            // follow-up to the UIPageViewController refactor.
            swapChapter(to: href, jumpToLastPage: true)

        case .atEndOfBook, .atStartOfBook:
            // Future: trigger "Finished?" prompt (§13.6) or a subtle
            // haptic to signal the boundary.
            break
        }
    }

    private func swapChapter(to href: String, jumpToLastPage: Bool) {
        viewModel.pendingJumpToLastPage = jumpToLastPage
        viewModel.currentChapterHref = href
        if let spine = viewModel.parsed?.spine {
            viewModel.pagination.willLoadChapter(
                spineIndex: PageNavigator.spineIndex(of: href, in: spine) ?? 0,
                spineCount: spine.count
            )
        }
    }

    // MARK: - Helpers

    func currentChapterURL() -> URL? {
        guard let parsed = viewModel.parsed,
              let href = viewModel.currentChapterHref else { return nil }
        return parsed.spine
            .first(where: { $0.href == href })?
            .absoluteURL
            ?? parsed.unzippedRoot.appendingPathComponent(href)
    }

    /// File URL of the FIRST page of the next chapter in the spine, or
    /// nil if the current chapter is the last one in the book. Used by
    /// `PaginatedChapterView` to fill the right-hand slot of an iPad-
    /// landscape Page Curl spread when the current chapter doesn't
    /// have enough pages of its own to fill it (most commonly: a
    /// 1-page front-matter chapter like a title page).
    func nextChapterURLAfterCurrent() -> URL? {
        guard let parsed = viewModel.parsed,
              let href = viewModel.currentChapterHref,
              let idx = parsed.spine.firstIndex(where: { $0.href == href }),
              idx + 1 < parsed.spine.count
        else { return nil }
        return parsed.spine[idx + 1].absoluteURL
    }

    func transitionStyle() -> UIPageViewController.TransitionStyle {
        switch viewModel.effectivePageTurnStyle {
        case .curl:   return .pageCurl
        case .slide:  return .scroll
        case .scroll: return .scroll   // unreachable — scroll uses WKWebViewWrapper
        }
    }

    func pushLiveCSSUpdate() {
        if viewModel.paginatedMode {
            // Paginated modes display pre-rendered UIImages, not live
            // WebViews, so a CSS-injection trick can't update what the
            // user sees. Instead we invalidate the chapter's cached
            // images and re-render with the new CSS. The current page
            // updates first (priority order), then adjacent pages
            // backfill — the user sees their current page redraw
            // within ~200–400ms.
            viewModel.invalidateCurrentChapterAndRerender()
        } else if let web = scrollWebView {
            // Scroll mode is still a live WKWebView — push CSS as JS
            // for instant in-place restyling.
            let js = UserScriptBuilder.liveUpdateJS(css: viewModel.currentCSS())
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
