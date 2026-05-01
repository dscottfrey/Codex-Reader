//
//  ReaderSettingsPanel.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The bottom-sheet typography panel ("Aa") shown from the reader's
//  options panel. Defined in Module 1 (Rendering Engine) §4.2.
//
//  WHAT'S HERE IN v1 SCAFFOLDING:
//  - Typography mode picker (Publisher / My Defaults / Custom). What
//    used to be a forced first-open prompt now lives here, accessible
//    any time the user wants to switch how this book is being styled.
//  - Surface controls: font size, font family, line spacing, theme,
//    page-turn style.
//
//  WHAT'S DEFERRED TO LATER:
//  - "More Typography…" expand-in-place (letter spacing, alignment,
//    margins, use book fonts).
//  - "Clear book settings" / reset to publisher.
//  - First-open typography prompt (TypographyPromptView is still in
//    the codebase but no longer triggered automatically; see
//    ReaderViewModel.loadBook). Moving the choice into this panel
//    matches Scott's preferred UX and avoids a forced gate on first
//    open.
//
//  WHY THE LIVE-UPDATE PATH IS DEBOUNCED:
//  The page render pipeline re-renders the WHOLE chapter when CSS
//  changes. Without debouncing, every slider step (8pt → 9pt → 10pt
//  → …) would invalidate the cache and start a new render task. A
//  500ms drag would queue ~10 render tasks, each cancelling its
//  predecessor mid-snapshot — none completes, the user sees nothing
//  update. Debouncing collapses the slider drag into a single
//  re-render fired ~250ms after the user stops moving.
//

import SwiftUI

/// The reader's bottom-sheet typography panel.
struct ReaderSettingsPanel: View {

    // MARK: - Inputs

    @Bindable var viewModel: ReaderViewModel

    /// Notifies the host that a value changed and the displayed
    /// content should be re-rendered. Called via the debounced
    /// wrapper below.
    let onLiveChange: () -> Void

    /// Dismisses the sheet. Wired explicitly by the host
    /// (`ReaderView`) rather than via `@Environment(\.dismiss)`:
    /// `.presentationDetents` panels rely on iOS swipe-down to
    /// dismiss, but the form's sliders capture vertical drags and
    /// swallow the gesture. The environment dismiss has also proved
    /// unreliable when the panel re-evaluates rapidly during slider
    /// drags. The explicit closure matches the pattern
    /// `TypographyPromptView` uses, which has not had the same issue.
    let onDone: () -> Void

    /// In-flight debounce task — cancelled and replaced on every
    /// change so a rapid slider drag results in exactly one re-render
    /// fired ~250ms after the user lets go.
    @State private var debounceTask: Task<Void, Never>?

    init(
        viewModel: ReaderViewModel,
        onLiveChange: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self._viewModel = Bindable(viewModel)
        self.onLiveChange = onLiveChange
        self.onDone = onDone
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Style") {
                    Picker("Mode", selection: typographyModeBinding) {
                        Text("Publisher").tag(BookTypographyMode.publisherDefault)
                        Text("My Defaults").tag(BookTypographyMode.userDefaults)
                        Text("This Book Only").tag(BookTypographyMode.custom)
                    }
                    .pickerStyle(.segmented)

                    Text(modeDescription(for: viewModel.book.typographyMode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.book.typographyMode != .publisherDefault {
                    Section("Typography") {
                        fontSizeRow
                        lineSpacingRow
                        fontFamilyRow
                    }

                    Section("Margins") {
                        marginTopRow
                        marginBottomRow
                        marginLeftRow
                        marginRightRow
                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                        .bold()
                }
            }
            .onAppear { captureInitialStateIfNeeded() }
        }
    }

    // MARK: - Rows

    /// Font-size row uses a Stepper rather than a Slider with a
    /// numeric label. The pt value is intentionally not shown — see
    /// Docs/HANDOFF.md §2.2 ("Off-screen renderer half-size
    /// rendering"): the slider's reported pt didn't match the
    /// rendered output, so showing it was misleading. Up/down arrows
    /// let the user adjust by feel until the page looks right,
    /// without committing to a number that doesn't match reality.
    private var fontSizeRow: some View {
        Stepper(
            "Font size",
            value: fontSizeBinding,
            in: 8...72,
            step: 1
        )
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
        Stepper(
            value: lineSpacingBinding,
            in: 1.0...2.5,
            step: 0.1
        ) {
            Text(String(format: "Line spacing: %.1f×", currentSettings.lineSpacing))
        }
    }

    // MARK: - Margin rows
    //
    // Top / Bottom / Left / Right margins, each in points. Range is
    // 0–250pt in 5pt increments — wider than what a print designer
    // would normally need, because the off-screen renderer's
    // half-size bug (Docs/HANDOFF.md §2.2) means CSS pt values
    // render at roughly half their nominal size. A user wanting a
    // visual 100pt top margin currently has to set 200pt. Once the
    // half-size issue is fixed properly the range can drop back to
    // something like 0–80pt.
    //
    // Per-page asymmetric margins (an outer-margin / gutter split
    // that mirrors a printed book's binding) is NOT implemented
    // here. The current pipeline renders both pages of a spread
    // from the same CSS, so left/right padding is symmetric across
    // both pages. Logged as a follow-up in HANDOFF.

    private var marginTopRow: some View {
        Stepper(
            value: marginTopBinding,
            in: 0...250,
            step: 5
        ) {
            Text("Top: \(Int(currentSettings.marginTop))pt")
        }
    }

    private var marginBottomRow: some View {
        Stepper(
            value: marginBottomBinding,
            in: 0...250,
            step: 5
        ) {
            Text("Bottom: \(Int(currentSettings.marginBottom))pt")
        }
    }

    private var marginLeftRow: some View {
        Stepper(
            value: marginLeftBinding,
            in: 0...250,
            step: 5
        ) {
            Text("Left: \(Int(currentSettings.marginLeft))pt")
        }
    }

    private var marginRightRow: some View {
        Stepper(
            value: marginRightBinding,
            in: 0...250,
            step: 5
        ) {
            Text("Right: \(Int(currentSettings.marginRight))pt")
        }
    }

    // MARK: - Bindings

    /// The settings struct currently being edited — depends on the
    /// book's typography mode. In Publisher mode this still returns
    /// the global settings, but the typography sliders are hidden so
    /// edits don't reach this path.
    private var currentSettings: ReaderSettings {
        switch viewModel.book.typographyMode {
        case .publisherDefault, .userDefaults:
            return viewModel.globalSettings
        case .custom:
            return viewModel.effective ?? viewModel.globalSettings
        }
    }

    /// Apply a change. Writes back to globalSettings or per-book
    /// overrides depending on the current typography mode.
    ///
    /// Publisher mode is treated like My Defaults for the purposes of
    /// Theme and Page Turn — those are global preferences, not
    /// typography that publisher mode should suppress. The typography
    /// rows themselves are hidden in publisher mode (see body), so
    /// only theme / page-turn writes can reach this in that mode.
    private func apply(_ mutate: (inout ReaderSettings) -> Void) {
        switch viewModel.book.typographyMode {
        case .publisherDefault, .userDefaults:
            var s = viewModel.globalSettings
            mutate(&s)
            viewModel.globalSettings = s
            // TODO: persist to ReaderSettingsRecord via the model context.
        case .custom:
            var merged = viewModel.effective ?? viewModel.globalSettings
            mutate(&merged)
            viewModel.book.typographyOverrides = makeOverrides(from: merged)
        }
        scheduleLiveChange()
    }

    /// Debounced wrapper around `onLiveChange`. Cancels any pending
    /// re-render and schedules a fresh one ~250ms in the future. A
    /// rapid slider drag therefore produces a single re-render after
    /// the user lets go — not one per slider step.
    private func scheduleLiveChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            onLiveChange()
        }
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

    /// Short prose explanation shown beneath the mode picker. Helps the
    /// user understand what each mode does without forcing a separate
    /// help screen.
    private func modeDescription(for mode: BookTypographyMode) -> String {
        switch mode {
        case .publisherDefault:
            return "Use the publisher's styling for this book."
        case .userDefaults:
            return "Apply your global typography preferences to every book."
        case .custom:
            return "Customise typography just for this book."
        }
    }

    // MARK: - Cancel / restore

    /// Snapshot of state captured when the panel is first presented,
    /// used to discard changes when the user taps Cancel. Captured
    /// once via `.onAppear` so changes during the panel's lifetime
    /// don't overwrite the baseline.
    @State private var initialState: PanelState?

    /// All the state that Cancel needs to restore.
    private struct PanelState {
        let globalSettings: ReaderSettings
        let typographyMode: BookTypographyMode
        let typographyOverrides: BookReaderOverrides
    }

    private func captureInitialStateIfNeeded() {
        guard initialState == nil else { return }
        initialState = PanelState(
            globalSettings: viewModel.globalSettings,
            typographyMode: viewModel.book.typographyMode,
            typographyOverrides: viewModel.book.typographyOverrides
        )
    }

    /// Restore the snapshotted state and trigger a re-render so the
    /// chapter image cache reflects the original CSS again. Then
    /// dismiss.
    private func cancel() {
        debounceTask?.cancel()
        if let state = initialState {
            viewModel.globalSettings           = state.globalSettings
            viewModel.book.typographyMode      = state.typographyMode
            viewModel.book.typographyOverrides = state.typographyOverrides
        }
        // Re-render synchronously (well, fire the task — the user
        // accepted a render delay on cancel). No debounce here; we
        // want this to start immediately.
        onLiveChange()
        onDone()
    }

    // MARK: - Bindings

    private var typographyModeBinding: Binding<BookTypographyMode> {
        Binding(
            get: { viewModel.book.typographyMode },
            set: { newMode in
                let oldMode = viewModel.book.typographyMode
                guard newMode != oldMode else { return }
                viewModel.book.typographyMode = newMode
                // When entering Custom from another mode, seed the
                // book's overrides from whatever was being applied
                // before — the user's expectation is "start from
                // where I am now and customise." Skip seeding if the
                // book already has customisations stored.
                if newMode == .custom && viewModel.book.typographyOverrides.isEmpty {
                    let starting = (oldMode == .publisherDefault)
                        ? viewModel.globalSettings
                        : (viewModel.effective ?? viewModel.globalSettings)
                    viewModel.book.typographyOverrides = makeOverrides(from: starting)
                }
                // When leaving Custom, drop the overrides so the book
                // truly reverts to publisher / global rather than
                // silently retaining customised values. The Book
                // model's accessor treats `.empty` as "clear the
                // stored blob."
                if oldMode == .custom && newMode != .custom {
                    viewModel.book.typographyOverrides = .empty
                }
                scheduleLiveChange()
            }
        )
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
    private var marginTopBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.marginTop },
                set: { newValue in apply { $0.marginTop = newValue } })
    }
    private var marginBottomBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.marginBottom },
                set: { newValue in apply { $0.marginBottom = newValue } })
    }
    private var marginLeftBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.marginLeft },
                set: { newValue in apply { $0.marginLeft = newValue } })
    }
    private var marginRightBinding: Binding<CGFloat> {
        Binding(get: { currentSettings.marginRight },
                set: { newValue in apply { $0.marginRight = newValue } })
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
