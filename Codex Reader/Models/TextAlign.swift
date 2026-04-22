//
//  TextAlign.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The text alignment choices for the body of a book. Module 1 (Rendering
//  Engine) §2.8 lists exactly two: left-aligned and justified. Anything more
//  (centre, right) is not meaningful for prose body text and is not offered.
//
//  WHY IT EXISTS:
//  CSSBuilder needs the literal CSS value ("left" or "justify"). Putting the
//  mapping here keeps the renderer free of magic strings.
//

import Foundation

/// Text alignment for the body of an epub. Only the two reading-meaningful
/// values are exposed.
enum TextAlign: String, Codable, CaseIterable, Identifiable {
    case left
    case justified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:      return "Left"
        case .justified: return "Justified"
        }
    }

    /// The exact CSS `text-align` keyword to inject into the WKWebView.
    /// Note: CSS uses `justify`, not `justified` — the rawValue and the CSS
    /// keyword are deliberately allowed to differ.
    var cssValue: String {
        switch self {
        case .left:      return "left"
        case .justified: return "justify"
        }
    }
}
