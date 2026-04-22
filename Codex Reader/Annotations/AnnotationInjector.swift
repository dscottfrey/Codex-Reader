//
//  AnnotationInjector.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Injects the JavaScript that draws highlight overlays and margin note
//  markers into the WKWebView after a chapter renders. Defined in
//  Module 6 (Annotation System) §3.4 and Rendering Engine §3.4.
//
//  WHY POST-RENDER:
//  Annotations sit ON TOP of the final styled content. If we injected
//  them before the user CSS was applied, the highlight bounding boxes
//  would be wrong (positioned against the publisher's layout, not the
//  user's). The renderer calls into us from `webView(_:didFinish:)` —
//  which is the documented post-render hook — so we always run on the
//  final rendered DOM.
//
//  WHY CHARACTER OFFSETS AS THE COORDINATE SYSTEM:
//  The directive (Annotation §5) is explicit: highlights are stored as
//  start/end character offsets within the chapter's plain-text
//  content. Character offsets survive font-size changes, page turns,
//  and re-renders — pixel coordinates would not. The JS we inject walks
//  the chapter's text nodes counting characters until it hits the
//  highlight's range, then wraps the matching text in a styled span.
//

import Foundation
@preconcurrency import WebKit

@MainActor
struct AnnotationInjector {

    let store: AnnotationStore

    /// Run the highlight overlay script for one chapter. Pulls live
    /// annotations from the store, builds a JSON payload, and hands
    /// it to a JavaScript helper that walks the DOM and wraps the
    /// matching ranges.
    func injectAnnotations(
        forBookID bookID: UUID,
        chapterHref: String,
        into webView: WKWebView
    ) {
        let annotations = store.annotations(forBookID: bookID, chapterHref: chapterHref)
        let payload = annotations.map { json($0) }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: payloadData, encoding: .utf8)
        else { return }

        let js = injectionJS(payload: payloadString)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - JS payload

    /// Convert an Annotation to the JSON shape the injection JS
    /// expects. Stays in lock-step with the JS — both ends are
    /// maintained in this file so they cannot drift.
    private func json(_ a: Annotation) -> [String: Any] {
        var obj: [String: Any] = [
            "id": a.id.uuidString,
            "type": a.type.rawValue,
            "start": a.startOffset,
            "end": a.endOffset
        ]
        if let color = a.highlightColor { obj["color"] = colorCSS(color) }
        if let note = a.noteText, !note.isEmpty { obj["hasNote"] = true }
        return obj
    }

    /// Map our highlight-colour enum to a CSS rgba() string. Opacity
    /// matches the directive's recommended values from §5
    /// (HighlightColor.color in the directive's Swift snippet).
    private func colorCSS(_ color: HighlightColor) -> String {
        switch color {
        case .yellow: return "rgba(255, 235, 59, 0.40)"
        case .green:  return "rgba(76, 175, 80, 0.40)"
        case .blue:   return "rgba(33, 150, 243, 0.30)"
        case .pink:   return "rgba(233, 30, 99, 0.30)"
        case .orange: return "rgba(255, 152, 0, 0.35)"
        }
    }

    // MARK: - JS source

    /// The JavaScript that finds the right text nodes and wraps the
    /// highlight ranges. Self-contained — it reads the JSON payload
    /// passed in, walks the body's text nodes counting characters,
    /// and wraps matching ranges in a <span class="codex-hl"> with the
    /// requested colour. Runs once per chapter render.
    ///
    /// This is intentionally simple — a future iteration will need to
    /// handle margin-note markers and the §3.2 tap-to-open-popover
    /// path, but the foundation is the same offset-walker.
    private func injectionJS(payload: String) -> String {
        return """
        (function() {
          var annotations = \(payload);
          if (!annotations || !annotations.length) return;

          // Walk all text nodes inside the body and number their
          // characters. We use a TreeWalker for the DOM walk because
          // it is the standard primitive for this kind of traversal.
          var walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null,
            false
          );
          var pieces = [];
          var pos = 0;
          var node;
          while ((node = walker.nextNode())) {
            var len = node.nodeValue.length;
            pieces.push({ node: node, start: pos, end: pos + len });
            pos += len;
          }

          annotations.forEach(function(a) {
            wrapRange(pieces, a);
          });

          function wrapRange(pieces, a) {
            // Find the start/end pieces by character position.
            var startPiece = null, endPiece = null;
            for (var i = 0; i < pieces.length; i++) {
              if (a.start >= pieces[i].start && a.start < pieces[i].end) {
                startPiece = pieces[i];
              }
              if (a.end > pieces[i].start && a.end <= pieces[i].end) {
                endPiece = pieces[i];
                break;
              }
            }
            if (!startPiece || !endPiece) return;

            var range = document.createRange();
            range.setStart(startPiece.node, a.start - startPiece.start);
            range.setEnd(endPiece.node, a.end - endPiece.start);

            var span = document.createElement('span');
            span.className = 'codex-hl';
            span.dataset.annotationId = a.id;
            span.style.backgroundColor = a.color || 'transparent';
            try { range.surroundContents(span); } catch (e) {
              // surroundContents fails when the range crosses element
              // boundaries — we accept the failure silently for now;
              // a future iteration can split the range manually.
            }
          }
        })();
        """
    }
}
