//
//  UserScriptBuilder.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Wraps a CSS string into a `WKUserScript` that injects it into a
//  WKWebView's <head> at document start. Defined in Module 1 (Rendering
//  Engine) §3.3.
//
//  WHY DOCUMENT-START IS CRUCIAL:
//  Injecting at document END (or via JavaScript after load) creates a
//  visible "flash of unstyled content" — the user sees the publisher's
//  styling for a fraction of a second before our overrides kick in. By
//  inserting our <style> tag BEFORE the epub HTML is parsed, the cascade
//  has our overrides in place from frame zero. No flash, no flicker.
//
//  WHY THE CSS IS JSON-ENCODED:
//  We embed the CSS into a JavaScript string literal. Naively
//  string-interpolating it would break on any quote, backslash, or newline
//  in the CSS. JSON encoding produces a string the JS parser is
//  guaranteed to accept verbatim — quotes, escapes, newlines and all. The
//  alternative (manual escape-everything-yourself) is a known footgun and
//  was tried in earlier internal iterations; this approach is the safe one.
//

import Foundation
@preconcurrency import WebKit

/// Build the `WKUserScript` and the live-update JavaScript string that
/// the renderer needs.
enum UserScriptBuilder {

    /// The DOM id we tag our injected <style> element with. The live
    /// update path looks for this id to update the rules in-place without
    /// a page reload — see `liveUpdateJS(css:)`.
    static let styleElementID = "codex-user-prefs"

    /// Build a WKUserScript that, when added to a WKWebView's
    /// userContentController, inserts a <style> element at document start.
    static func makeUserScript(css: String) -> WKUserScript {
        let js = injectionJS(css: css)
        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// Build the pagination/navigation user script (see PaginationJS).
    /// `paginated` = true for Slide (and eventually Curl); false for
    /// Scroll mode, where the JS leaves the document alone and just
    /// reports scroll progress.
    static func makePaginationScript(paginated: Bool) -> WKUserScript {
        WKUserScript(
            source: PaginationJS.makeScript(paginated: paginated),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// JavaScript that creates the <style> element and appends it to
    /// document.head. Used both by the document-start user script and (in
    /// rare cases) by an evaluateJavaScript call after a navigation.
    static func injectionJS(css: String) -> String {
        let encoded = jsStringLiteral(css)
        return """
        (function() {
          var existing = document.getElementById('\(styleElementID)');
          if (existing) { existing.parentNode.removeChild(existing); }
          var style = document.createElement('style');
          style.id = '\(styleElementID)';
          style.innerHTML = \(encoded);
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    /// JavaScript for the LIVE UPDATE path: when the user is dragging a
    /// font-size slider, we don't want to reload the page on every
    /// frame. Instead we mutate the existing style element in-place. If
    /// the element doesn't exist (rare timing case) we create it.
    static func liveUpdateJS(css: String) -> String {
        let encoded = jsStringLiteral(css)
        return """
        (function() {
          var s = document.getElementById('\(styleElementID)');
          if (!s) {
            s = document.createElement('style');
            s.id = '\(styleElementID)';
            (document.head || document.documentElement).appendChild(s);
          }
          s.innerHTML = \(encoded);
        })();
        """
    }

    /// Encode an arbitrary string as a JavaScript string literal —
    /// quotes, escapes, newlines all handled by JSONEncoder. Returns the
    /// literal complete with surrounding quotes, ready to be dropped into
    /// JavaScript source.
    ///
    /// Falls back to `""` (empty literal) if encoding ever fails — safer
    /// than crashing the renderer over a CSS construction bug.
    private static func jsStringLiteral(_ raw: String) -> String {
        guard let data = try? JSONEncoder().encode(raw),
              let literal = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return literal
    }
}
