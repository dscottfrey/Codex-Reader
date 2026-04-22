//
//  ReaderChromeView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The two thin chrome strips — title at the top, page metadata at the
//  bottom — that fade in when the user taps the reading surface. Defined
//  in Module 1 (Rendering Engine) §4.1.
//
//  WHY SEPARATE FROM ReaderView:
//  ReaderView is already the orchestration of many subviews (chrome,
//  webview, bookmark ribbon, options panel, settings sheet). Pulling the
//  chrome out into one focused view keeps each file under the 200-line
//  guideline and makes the chrome layout legible on its own.
//

import SwiftUI

/// The thin "tap to reveal" chrome above and below the reading surface.
///
/// The surface itself is rendered by ReaderView; this view sits on top
/// of it as an overlay and is shown/hidden by toggling its opacity. The
/// reading text underneath is unaffected — these strips do not push the
/// text down or change pagination.
struct ReaderChromeView: View {

    // MARK: - Inputs

    /// Whether the chrome is currently visible.
    let visible: Bool

    /// What to show in the title strip — typically the book or chapter
    /// title (the choice between book and chapter is in Settings).
    let titleText: String

    /// What to show in the metadata strip — chapter / page / pages
    /// remaining etc., already formatted by the caller.
    let metadataText: String

    /// The theme, for matching the strip background to the reading
    /// surface in skeuomorphic mode (and for sane Dark/Sepia colours
    /// otherwise).
    let theme: ReaderTheme

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            Spacer()
            metadataStrip
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: visible)
        .allowsHitTesting(false)  // chrome is decorative — the underlying tap zones still work
    }

    // MARK: - Subviews

    private var titleStrip: some View {
        Text(titleText)
            .font(.footnote)
            .foregroundStyle(theme.textColor.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var metadataStrip: some View {
        Text(metadataText)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(theme.textColor.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
