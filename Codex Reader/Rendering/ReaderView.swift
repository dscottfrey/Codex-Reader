//
//  ReaderView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The top-level reader screen — composes the reading surface, the
//  chrome overlays, the bookmark ribbon, and the entry points to the
//  options panel and settings sheet.
//
//  WHY IT'S "JUST ASSEMBLY":
//  Per §6.3, views don't contain business logic. ReaderView composes
//  ReaderChromeView, BookmarkRibbonView, and one of two page-turn
//  surfaces (PaginatedChapterView for Curl/Slide, WKWebViewWrapper for
//  Scroll — see ReaderView+Surfaces). State and logic live in
//  ReaderViewModel; surface selection and tap handling live in the
//  Surfaces extension file.
//

import SwiftUI
import SwiftData
@preconcurrency import WebKit

struct ReaderView: View {

    @State var viewModel: ReaderViewModel

    /// Called when the user closes the book — ContentView clears its
    /// `openBook` state and returns to the library. Optional so preview
    /// / test callers can omit it.
    var onClose: () -> Void = {}

    /// The scroll-mode WKWebView, for live CSS updates.
    @State var scrollWebView: WKWebView?

    /// The paginated coordinator, for tap-zone-driven turns and live
    /// updates in Curl/Slide modes. Held as a reference so ReaderView
    /// can call `turnPage(direction:)` without going through SwiftUI
    /// state re-renders.
    @State var paginatedCoord: PaginatedChapterView.Coordinator?

    /// The currently-presented sheet, if any. Using a single
    /// `.sheet(item:)` (rather than stacking two `.sheet(isPresented:)`
    /// modifiers) avoids a SwiftUI pitfall where the second sheet
    /// gets into a "presented once or twice, then stops" state
    /// because the two bindings interfere with each other's
    /// dismissal animation.
    @State private var activeSheet: ReaderSheet?

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ZStack {
            readingSurface
                .ignoresSafeArea()

            tapZones

            ReaderChromeView(
                visible: viewModel.chromeVisible,
                titleText: viewModel.book.title,
                metadataText: metadataText(),
                theme: viewModel.theme,
                onClose: {
                    // Flush the current position before leaving so
                    // "resume where I was" works on reopen.
                    Task {
                        await viewModel.savePositionNow()
                        onClose()
                    }
                },
                onOpenSettings: {
                    activeSheet = .settings
                }
            )

            // Bookmark ribbon — always visible (§4.7).
            VStack {
                HStack {
                    Spacer()
                    BookmarkRibbonView(
                        isBookmarked: false,    // TODO: wire to AnnotationStore lookup for current chapter+offset
                        onTap: { /* TODO: toggle bookmark */ },
                        onLongPress: { /* TODO: open inline label editor */ }
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

            if viewModel.parsed == nil && viewModel.loadError == nil {
                ProgressView("Opening book…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = viewModel.loadError {
                errorOverlay(error)
            }
        }
        .task { await viewModel.loadBook() }
        .onDisappear { Task { await viewModel.savePositionNow() } }
        .onChange(of: viewModel.typographyPromptShown) { _, shown in
            // The view model flips this flag from loadBook() on first
            // open — relay it into the single-sheet presenter so only
            // one sheet source drives SwiftUI's presentation.
            if shown { activeSheet = .typographyPrompt }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ReaderSheet) -> some View {
        switch sheet {
        case .typographyPrompt:
            TypographyPromptView(
                book: viewModel.book,
                onChoice: { _ in
                    viewModel.typographyPromptShown = false
                    activeSheet = nil
                }
            )
        case .settings:
            ReaderSettingsPanel(viewModel: viewModel) {
                pushLiveCSSUpdate()
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Surface dispatch

    @ViewBuilder
    private var readingSurface: some View {
        if viewModel.paginatedMode {
            paginatedSurface
        } else {
            scrollSurface
        }
    }

    // MARK: - Tap zones

    /// Transparent tap zones overlaid on the reading surface.
    ///
    /// WHY `.simultaneousGesture` RATHER THAN `.onTapGesture`:
    /// `.onTapGesture` on a view with `.contentShape(Rectangle())`
    /// eats the entire touch sequence — tap, pan, everything — which
    /// was blocking WKWebView's vertical scroll in Scroll mode.
    /// `.simultaneousGesture(TapGesture())` registers a tap recogniser
    /// that runs alongside the WKWebView's own gestures, so pans pass
    /// through to the web view naturally.
    ///
    /// WHY LEFT/RIGHT ZONES ONLY IN PAGINATED MODE:
    /// In Scroll mode there are no "previous page" or "next page"
    /// concepts — the chapter is one continuous scroll. A left tap
    /// in Scroll mode shouldn't do anything, so we just don't install
    /// those zones. The centre chrome-toggle zone stays everywhere.
    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if viewModel.paginatedMode {
                    tapZone(width: geo.size.width * 0.35,
                            action: handlePrevPageTap)
                } else {
                    Color.clear.frame(width: geo.size.width * 0.35)
                        .allowsHitTesting(false)
                }

                tapZone(width: geo.size.width * 0.30,
                        action: viewModel.toggleChrome)

                if viewModel.paginatedMode {
                    tapZone(width: geo.size.width * 0.35,
                            action: handleNextPageTap)
                } else {
                    Color.clear.frame(width: geo.size.width * 0.35)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func tapZone(width: CGFloat, action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { action() }
            )
    }

    // MARK: - Bottom-of-file helpers

    private func metadataText() -> String {
        // TODO: assemble from Advanced Settings toggles (§4.5).
        let p = viewModel.pagination
        if p.paginated {
            // Book-level position ("Page X of Y") with chapter-level
            // remaining count. The book totals are approximate until
            // every chapter has been measured — see PaginationEngine's
            // chapterPageCounts comment.
            return "\(p.shortPositionLabel), \(p.pagesRemainingInChapter) left in chapter"
        }
        return p.shortPositionLabel
    }

    /// Identifier for the single presentation slot the reader uses
    /// for modal sheets. `.sheet(item:)` with this enum avoids the
    /// SwiftUI pitfall of stacking multiple `.sheet(isPresented:)`
    /// modifiers on one view.
    enum ReaderSheet: String, Identifiable {
        case typographyPrompt
        case settings
        var id: String { rawValue }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }
}
