//
//  CSSBuilder.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Builds the CSS string that gets injected into every chapter's WKWebView
//  to apply the user's typography choices on top of the epub's own styles.
//  Defined in Module 1 (Rendering Engine) §3.3.
//
//  WHY IT EXISTS SEPARATELY:
//  The CSS string is the contract between Codex's Swift settings and the
//  WebKit rendering engine. Generating it in one place means the JS
//  injection path (UserScriptBuilder), the live-preview update path, and
//  the test code that verifies the CSS all use exactly the same generator.
//
//  WHY EVERYTHING USES !important:
//  Many epub stylesheets are aggressively specific (high-specificity
//  selectors, inline styles). Without `!important` the user's overrides
//  would be silently lost on a non-trivial fraction of books. The
//  directive (§2.2) is explicit that user prefs ALWAYS win.
//

import Foundation

/// Pure function: turn a typography decision (some `ReaderSettings` to
/// apply, or nil to mean "publisher mode") plus a theme and a safety
/// floor into a CSS string ready to be inserted into a `<style>` element
/// in the WKWebView.
enum CSSBuilder {

    /// Generate the user-overrides CSS for a chapter render.
    ///
    /// - Parameters:
    ///   - effective: The effective ReaderSettings (from
    ///     `effectiveSettings(global:book:)`). Pass `nil` when the book is
    ///     in publisher mode — only theme + floor will be injected.
    ///   - theme: The theme to use for background/text colour. Always
    ///     applied regardless of mode.
    ///   - publisherSafetyFloorPt: Minimum font size to enforce when
    ///     `effective` is nil. Default 10pt per directive §2.2.
    /// - Returns: A CSS string (no surrounding `<style>` tags).
    static func build(
        effective: ReaderSettings?,
        theme: ReaderTheme,
        publisherSafetyFloorPt: CGFloat = 10
    ) -> String {

        // The theme block runs in EVERY mode. It's the one user preference
        // that overrides publisher CSS unconditionally — see directive §4.6.
        let themeBlock = """
        html, body {
          background-color: \(theme.backgroundHex) !important;
          color: \(theme.textHex) !important;
        }
        """

        // PUBLISHER MODE: only the theme + the safety floor. We avoid
        // injecting anything else so the publisher's chosen typography
        // stands.
        guard let s = effective else {
            let floorBlock = """
            html, body, p, div, span, li, td, th {
              font-size: max(\(publisherSafetyFloorPt)pt, 1em) !important;
            }
            """
            return themeBlock + "\n" + floorBlock
        }

        // USER / CUSTOM MODE: the full override block.
        //
        // We target a small, generous list of element types — the
        // containers prose body text actually sits in. Targeting `*`
        // breaks code listings and other monospace elements; this list is
        // the directive's recommendation in §3.3.
        let typographyBlock = """
        html, body, p, div, span, li, td, th, blockquote {
          font-size: \(s.fontSize)pt !important;
          font-family: \(fontFamilyDeclaration(for: s)) !important;
          line-height: \(s.lineSpacing) !important;
          letter-spacing: \(s.letterSpacing)px !important;
          text-align: \(s.textAlignment.cssValue) !important;
        }
        body {
          padding: \(s.marginTop)pt \(s.marginRight)pt \(s.marginBottom)pt \(s.marginLeft)pt !important;
          margin: 0 !important;
        }
        """

        return themeBlock + "\n" + typographyBlock
    }

    /// Build the `font-family` declaration. When the user has set
    /// "Use book fonts" we respect the epub's chosen family by emitting
    /// `inherit` — meaning "do not override the font."
    ///
    /// Otherwise we name the chosen family with safe serif fallbacks so
    /// rendering never collapses if the font is missing.
    private static func fontFamilyDeclaration(for s: ReaderSettings) -> String {
        if s.useBookFonts {
            // `inherit` here keeps the !important specificity but defers
            // to whatever the cascade had decided — i.e., the epub's font.
            return "inherit"
        }
        return "'\(s.fontFamily)', Georgia, 'Times New Roman', serif"
    }
}
