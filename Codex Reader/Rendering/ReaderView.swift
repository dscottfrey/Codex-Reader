//
//  ReaderView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The top-level reader screen — the WKWebView surface, the chrome
//  overlays, the bookmark ribbon, and the entry points to the options
//  panel and settings sheet.
//
//  WHY IT'S "JUST ASSEMBLY":
//  Per the §6.3 rule, views don't contain business logic. ReaderView
//  composes ReaderChromeView, BookmarkRibbonView, the WKWebViewWrapper,
//  and the panels. State and logic live in ReaderViewModel.
//

import SwiftUI
@preconcurrency import WebKit

/// The full-screen reading view shown when the user opens a book.
struct ReaderView: View {

    // MARK: - State

    @State var viewModel: ReaderViewModel

    /// Live reference to the WKWebView held by the wrapper, so we can
    /// trigger live-update JavaScript on settings changes without
    /// reloading the page.
    @State private var webViewRef: WKWebView?

    // MARK: - Body

    var body: some View {
        ZStack {
            // The reading surface fills the screen. Tap zones (left/right
            // page-turn, centre chrome-toggle) sit on top as transparent
            // gesture areas.
            readingSurface
                .ignoresSafeArea()

            // Tap zones for page turns and chrome toggle (Rendering
            // Engine §4.1). Configurable via Advanced Settings; here we
            // use the default 35/30/35 split.
            tapZones

            // System 1 chrome — title strip + metadata strip overlay.
            ReaderChromeView(
                visible: viewModel.chromeVisible,
                titleText: viewModel.book.title,
                metadataText: metadataText(),
                theme: viewModel.theme
            )

            // The bookmark ribbon — always visible, in the top-trailing
            // corner per the standard mode layout (§4.7).
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

            // Loading / error overlays.
            if viewModel.parsed == nil && viewModel.loadError == nil {
                ProgressView("Opening book…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = viewModel.loadError {
                errorOverlay(error)
            }
        }
        .task {
            await viewModel.loadBook()
        }
        .sheet(isPresented: $viewModel.typographyPromptShown) {
            // First-open typography prompt — the only modal in the
            // reading flow. See §4.6.
            TypographyPromptView(
                book: viewModel.book,
                onChoice: { _ in
                    viewModel.typographyPromptShown = false
                }
            )
        }
        .sheet(isPresented: $viewModel.settingsPanelOpen) {
            ReaderSettingsPanel(viewModel: viewModel) {
                // When the panel changes settings, push a live CSS update
                // into the WKWebView without reloading the page.
                if let web = webViewRef {
                    let js = UserScriptBuilder.liveUpdateJS(css: viewModel.currentCSS())
                    web.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Reading surface

    @ViewBuilder
    private var readingSurface: some View {
        // The WKWebView wrapper, configured with the current user script.
        // Rebuilding the wrapper (because `userScript` changed) re-installs
        // the user script for the next navigation.
        WKWebViewWrapper(
            userScript: UserScriptBuilder.makeUserScript(css: viewModel.currentCSS()),
            webViewProxy: { web in
                self.webViewRef = web
                loadCurrentChapterIfNeeded(into: web)
            },
            onDidFinish: { _ in
                // TODO: hand off to AnnotationInjector for highlight overlays
                // and to the pagination engine for page count calculation.
            }
        )
        .background(viewModel.theme.backgroundColor)
    }

    // MARK: - Tap zones

    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left 35% — previous page
                Color.clear
                    .frame(width: geo.size.width * 0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { /* TODO: previous page */ }

                // Centre 30% — toggle chrome
                Color.clear
                    .frame(width: geo.size.width * 0.30)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleChrome() }

                // Right 35% — next page
                Color.clear
                    .frame(width: geo.size.width * 0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { /* TODO: next page */ }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private func loadCurrentChapterIfNeeded(into webView: WKWebView) {
        // Loading a chapter requires a real ParsedEpub. While the parser
        // is stubbed (EpubParserError.parserNotImplemented) viewModel.parsed
        // stays nil and we deliberately don't load anything — the user
        // sees the error overlay populated by `viewModel.loadError`.
        guard let parsed = viewModel.parsed,
              let href = viewModel.currentChapterHref else { return }
        let chapterURL = parsed.unzippedRoot.appendingPathComponent(href)
        // Allowing read access to the unzipped root lets the WKWebView
        // resolve relative asset references (CSS, images, fonts) within
        // the book's directory.
        webView.loadFileURL(chapterURL, allowingReadAccessTo: parsed.unzippedRoot)
    }

    private func metadataText() -> String {
        // TODO: assemble from Advanced Settings toggles (§4.5). For now,
        // a simple percentage so the strip isn't empty during development.
        let pct = Int((viewModel.book.readingProgress * 100).rounded())
        return "\(pct)% through"
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
