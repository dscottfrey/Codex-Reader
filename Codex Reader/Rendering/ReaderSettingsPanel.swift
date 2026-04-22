//
//  ReaderSettingsPanel.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The bottom-sheet typography panel ("Aa") shown from the reader's
//  options panel. Defined in Module 1 (Rendering Engine) §4.2.
//
//  WHAT'S HERE IN v1 SCAFFOLDING:
//  The "Surface controls" — font size, font family, line spacing, theme,
//  page-turn style, and margins — and the "Applies to: My Defaults / This
//  Book" segmented control that decides whether changes write to the
//  global ReaderSettings or to the book's per-book overrides.
//
//  WHAT'S DEFERRED TO LATER:
//  - "More Typography…" expand-in-place (letter spacing, alignment, use
//    book fonts).
//  - "Clear book settings" button.
//  - The starting-point selector and quick-apply switches that appear
//    only on the customise path from the first-open prompt — those live
//    in TypographyPromptView for now.
//

import SwiftUI

/// The reader's bottom-sheet typography panel. Calls `onLiveChange` after
/// every committed slider movement so the host (ReaderView) can push a
/// live-update CSS string into the WKWebView.
struct ReaderSettingsPanel: View {

    // MARK: - Inputs

    @Bindable var viewModel: ReaderViewModel

    /// Notifies the host that a value changed and the WKWebView should
    /// be live-updated. The host is the only place that holds the
    /// WKWebView reference, so we go through this callback.
    let onLiveChange: () -> Void

    /// Whether the panel is editing global defaults or the per-book
    /// overrides. Initialised based on whether the book is in custom
    /// mode (§4.2 — "the panel opens with This Book pre-selected when
    /// custom settings are active").
    @State private var scope: PanelScope

    init(viewModel: ReaderViewModel, onLiveChange: @escaping () -> Void) {
        self._viewModel = Bindable(viewModel)
        self.onLiveChange = onLiveChange
        self._scope = State(initialValue:
            viewModel.book.typographyMode == .custom ? .thisBook : .myDefaults
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Applies to", selection: $scope) {
                        Text("My Defaults").tag(PanelScope.myDefaults)
                        Text("This Book").tag(PanelScope.thisBook)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Typography") {
                    fontSizeRow
                    fontFamilyRow
                    lineSpacingRow
                }

                Section("Theme") {
                    Picker("Theme", selection: themeBinding) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Page Turn") {
                    Picker("Page Turn Style", selection: pageTurnBinding) {
                        ForEach(PageTurnStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Rows

    private var fontSizeRow: some View {
        VStack(alignment: .leading) {
            Text("Font size: \(Int(currentSettings.fontSize))pt")
                .font(.subheadline)
            Slider(
                value: fontSizeBinding,
                in: 8...72,
                step: 1
            ) { _ in onLiveChange() }
        }
    }

    private var fontFamilyRow: some View {
        // Minimal v1 list. TODO: pull from UIFont.familyNames so user-
        // installed custom fonts show up automatically (directive §2.4).
        Picker("Font", selection: fontFamilyBinding) {
            ForEach(["Georgia", "New York", "Palatino", "Helvetica Neue", "Times New Roman"], id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private var lineSpacingRow: some View {
        VStack(alignment: .leading) {
            Text(String(format: "Line spacing: %.1f×", currentSettings.lineSpacing))
                .font(.subheadline)
            Slider(
                value: lineSpacingBinding,
                in: 1.0...2.5,
                step: 0.1
            ) { _ in onLiveChange() }
        }
    }

    // MARK: - Bindings

    /// The settings struct currently being edited — depending on `scope`,
    /// either the global record or the merged per-book effective values.
    private var currentSettings: ReaderSettings {
        switch scope {
        case .myDefaults: return viewModel.globalSettings
        case .thisBook:
            return viewModel.effective ?? viewModel.globalSettings
        }
    }

    /// Apply a change. Writes back to the global settings or to the
    /// per-book overrides depending on scope, and switches typography
    /// mode appropriately when the user touches a per-book control.
    private func apply(_ mutate: (inout ReaderSettings) -> Void) {
        switch scope {
        case .myDefaults:
            var s = viewModel.globalSettings
            mutate(&s)
            viewModel.globalSettings = s
            // TODO: persist to ReaderSettingsRecord via the model context.
        case .thisBook:
            // Switching to per-book mode means leaving publisher/userDefaults
            // and entering custom mode (§7.2).
            viewModel.book.typographyMode = .custom
            var merged = viewModel.effective ?? viewModel.globalSettings
            mutate(&merged)
            viewModel.book.typographyOverrides = makeOverrides(from: merged)
        }
        onLiveChange()
    }

    /// Project a fully-populated ReaderSettings down to a per-book
    /// overrides record where every field is set (the user has touched
    /// at least something to be in this branch). A future refinement
    /// would only set fields that actually differ from the global —
    /// the directive (§7.3) describes that as the goal.
    private func makeOverrides(from s: ReaderSettings) -> BookReaderOverrides {
        var o = BookReaderOverrides.empty
        let g = viewModel.globalSettings
        if s.fontSize      != g.fontSize      { o.fontSize      = s.fontSize }
        if s.fontFamily    != g.fontFamily    { o.fontFamily    = s.fontFamily }
        if s.useBookFonts  != g.useBookFonts  { o.useBookFonts  = s.useBookFonts }
        if s.lineSpacing   != g.lineSpacing   { o.lineSpacing   = s.lineSpacing }
        if s.letterSpacing != g.letterSpacing { o.letterSpacing = s.letterSpacing }
        if s.textAlignment != g.textAlignment { o.textAlignment = s.textAlignment }
        if s.theme         != g.theme         { o.theme         = s.theme }
        if s.pageTurnStyle != g.pageTurnStyle { o.pageTurnStyle = s.pageTurnStyle }
        if s.marginTop     != g.marginTop     { o.marginTop     = s.marginTop }
        if s.marginBottom  != g.marginBottom  { o.marginBottom  = s.marginBottom }
        if s.marginLeft    != g.marginLeft    { o.marginLeft    = s.marginLeft }
        if s.marginRight   != g.marginRight   { o.marginRight   = s.marginRight }
        return o
    }

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.fontSize },
                set: { newValue in apply { $0.fontSize = newValue } })
    }
    private var fontFamilyBinding: Binding<String> {
        Binding(get: { currentSettings.fontFamily },
                set: { newValue in apply { $0.fontFamily = newValue } })
    }
    private var lineSpacingBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.lineSpacing },
                set: { newValue in apply { $0.lineSpacing = newValue } })
    }
    private var themeBinding: Binding<ReaderTheme> {
        Binding(get: { currentSettings.theme },
                set: { newValue in apply { $0.theme = newValue } })
    }
    private var pageTurnBinding: Binding<PageTurnStyle> {
        Binding(get: { currentSettings.pageTurnStyle },
                set: { newValue in apply { $0.pageTurnStyle = newValue } })
    }
}

/// Which typography surface the panel is currently editing.
private enum PanelScope: Hashable {
    case myDefaults
    case thisBook
}
