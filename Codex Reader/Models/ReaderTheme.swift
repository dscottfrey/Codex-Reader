//
//  ReaderTheme.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The reading themes (Light, Dark, Sepia) and their canonical background and
//  text colours. These constants are the single source of truth for theme
//  colours used by the reader's CSS injection, the SwiftUI chrome, and the
//  reader settings UI. Anywhere in the codebase that needs "the dark mode
//  background colour" should pull it from here.
//
//  WHY IT EXISTS:
//  Module 1 (Rendering Engine) §2.10 and §3.3 specify exact hex values for
//  each theme. Putting them in one file means:
//    1. The CSS injection string and the SwiftUI views show the same colour.
//    2. Adding a future "high contrast" theme is a one-line change here.
//    3. The values are not buried inside string interpolations elsewhere.
//

import SwiftUI

// MARK: - ReaderTheme

/// The three reading themes available in v1. The order matches the segmented
/// control order in Settings → Reading → Theme.
///
/// "Sepia" is a warm cream-on-brown reading surface — the classic e-reader
/// look that many readers prefer for long sessions.
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case sepia

    var id: String { rawValue }

    /// User-facing label for the theme picker.
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark:  return "Dark"
        case .sepia: return "Sepia"
        }
    }

    /// The hex string used inside the CSS injected into the WKWebView.
    /// Values come straight from the Rendering Engine directive §3.3.
    var backgroundHex: String {
        switch self {
        case .light: return "#FFFFFF"
        case .dark:  return "#1C1C1E"
        case .sepia: return "#F5EDD6"
        }
    }

    /// The hex string for body text colour, paired with the background.
    var textHex: String {
        switch self {
        case .light: return "#1C1C1E"
        case .dark:  return "#F2F2F7"
        case .sepia: return "#3B2A1A"
        }
    }

    /// SwiftUI Color version of `backgroundHex`. Used by Codex's own
    /// SwiftUI chrome (settings panel backdrop, etc.) so it visually matches
    /// what the WKWebView is showing.
    var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    /// SwiftUI Color version of `textHex`.
    var textColor: Color {
        Color(hex: textHex)
    }
}

// MARK: - Color hex helper

/// A small extension that lets us write `Color(hex: "#FFFFFF")`. SwiftUI does
/// not provide this initializer out of the box. Kept here (rather than in a
/// general-purpose Shared/ helper) because right now ReaderTheme is the only
/// caller — if other call sites appear, this can be moved.
extension Color {

    /// Build a SwiftUI Color from a hex string of the form `#RRGGBB` or
    /// `RRGGBB`. Invalid input falls back to opaque black so a typo never
    /// produces an invisible UI element.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8)  / 255.0
        let b = Double( rgb & 0x0000FF       ) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
