//
//  ReaderChromeView.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The tap-toggled chrome above and below the reading surface. A single
//  centre-tap reveals the whole strip — close button on the leading
//  edge, title in the middle, action icons (Aa for settings, and later
//  TOC / share / etc.) on the trailing edge, and the page-metadata
//  strip at the bottom. Tapping again hides it all.
//
//  WHY ONE CHROME, NOT TWO:
//  The directive (§4.1) originally described two chrome systems with
//  different invocation methods. Scott has collapsed them — the same
//  tap reveals both the "info" and "actions." See memory
//  "project_reader_chrome_invocation" for the rationale.
//
//  WHY THE METADATA STRIP ISN'T HIT-TESTABLE BUT THE ACTION BAR IS:
//  The metadata strip is decorative — letting it eat taps would
//  steal them from the underlying tap zones. The action bar needs
//  to receive taps (close, Aa, etc.), so we scope hit-testing to
//  that one row only.
//

import SwiftUI

struct ReaderChromeView: View {

    // MARK: - Inputs

    let visible: Bool

    /// What to show in the title strip — typically the book or chapter
    /// title (configurable in Advanced Settings).
    let titleText: String

    /// What to show in the metadata strip — chapter / page / pages
    /// remaining etc., already formatted by the caller.
    let metadataText: String

    /// Theme — drives the strip colours so they read against both
    /// Light and Dark reading surfaces.
    let theme: ReaderTheme

    /// Tapped the close (×) button — ReaderView propagates this up to
    /// the ContentView so the reader dismisses back to the library.
    let onClose: () -> Void

    /// Tapped the Aa button — ReaderView opens the settings sheet.
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Spacer()
            metadataStrip
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: visible)
    }

    // MARK: - Subviews

    /// Top bar — close (leading), title (centre), action icons (trailing).
    /// Hit-testing is restricted to this view so the decorative bottom
    /// strip doesn't swallow page-turn taps.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)  // §6 min tap target
            }
            .foregroundStyle(theme.textColor.opacity(0.8))
            .accessibilityLabel("Close book")

            Spacer(minLength: 0)

            Text(titleText)
                .font(.footnote)
                .foregroundStyle(theme.textColor.opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Text("Aa")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(theme.textColor.opacity(0.8))
            .accessibilityLabel("Reader settings")
        }
        // Extra trailing padding keeps the Aa icon clear of the
        // bookmark ribbon that lives in the same corner of the page.
        .padding(.leading, 12)
        .padding(.trailing, 48)
        .padding(.top, 4)
        // Subtle background so the icons have contrast against any
        // book page — light enough to not feel like a nav bar.
        .background(
            theme.backgroundColor.opacity(visible ? 0.92 : 0)
                .allowsHitTesting(false)
        )
        // Hit-testing on the bar itself — decorative chrome below is
        // disabled via the metadataStrip's own modifier.
        .allowsHitTesting(visible)
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
            .allowsHitTesting(false)   // decorative — don't eat taps
    }
}
