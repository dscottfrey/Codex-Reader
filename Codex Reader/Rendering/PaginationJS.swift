//
//  PaginationJS.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The JavaScript that runs inside every chapter-page WKWebView. It
//  does three things:
//
//    1. In paginated mode: applies CSS `column-width: 100vw` so the
//       chapter lays out as a horizontal strip of screen-wide columns,
//       then translates the body to show only one column. Each column
//       is one "page."
//    2. Reports total-page count and current-page back to Swift via
//       the script message handler.
//    3. Exposes `codexGoToPage(n)` and `codexSnapToPage(n)` for the
//       Swift side to jump between pages.
//
//  WHY NO TRANSITION ANIMATION:
//  Page-turn animations are handled by `UIPageViewController` (Curl
//  and Slide) or by WKWebView's native scroll (Scroll mode). This
//  script only draws the static content of ONE page; transitions are
//  a Swift/UIKit concern. Adding a CSS transition here would fight the
//  UIPageViewController animation when both tried to move the same
//  pixels.
//
//  SNAP vs GO:
//  - `codexSnapToPage(n)` — used by a page view controller at load
//    time to lock its web view to its assigned page. Does NOT post a
//    `pageChanged` message, because this is setup, not a user turn.
//  - `codexGoToPage(n)` — used for user-initiated jumps (scrubber,
//    TOC). Posts `pageChanged`.
//
//  MESSAGE HANDLER CONTRACT:
//  JS → Swift via `window.webkit.messageHandlers.codex`. Payloads are
//  `{type: ..., ...}` dicts; the Swift side's `PaginationMessage`
//  enum decodes them.
//

import Foundation

enum PaginationJS {

    /// The name of the `WKScriptMessageHandler` that the JS posts to.
    static let messageHandlerName = "codex"

    /// Build the JS source for a page-turn mode.
    ///
    /// - Parameter paginated: true for Curl/Slide, false for Scroll.
    static func makeScript(paginated: Bool) -> String {
        """
        (function() {
          var PAGINATED = \(paginated ? "true" : "false");

          function applyLayout() {
            var html = document.documentElement;
            var body = document.body;
            if (!body) return;
            if (PAGINATED) {
              // Use setProperty with 'important' so epub-author CSS
              // declarations with `!important` on body/html can't
              // override us. The default `element.style.x = ...`
              // syntax sets the style as inline-normal, which loses
              // the cascade against any `!important` in the book's
              // own stylesheet — that's the reason chapters rendered
              // as one giant column (totalPages = 1) before.
              function setI(el, name, value) {
                el.style.setProperty(name, value, 'important');
              }

              // Read CSSBuilder's resolved body padding BEFORE we
              // override anything. CSSBuilder injects the user's reading
              // margins (Settings → Reading → Typography → Margins) as
              // body padding. We need those numbers because the column
              // geometry below has to line up with the page-turn
              // translate distance — see the comment block on
              // 'column-width' below for the full explanation.
              var bodyCS = window.getComputedStyle(body);
              var padLeft   = parseFloat(bodyCS.paddingLeft)   || 0;
              var padRight  = parseFloat(bodyCS.paddingRight)  || 0;
              var padTop    = parseFloat(bodyCS.paddingTop)    || 0;
              var padBottom = parseFloat(bodyCS.paddingBottom) || 0;

              // Reserve a strip at the bottom of every page so the
              // chrome's metadata line (e.g. "Page 47 · 9 left in
              // chapter") never sits underneath body text when the user
              // taps to reveal the chrome. The reading surface ignores
              // safe areas, so the chrome lives in the same region the
              // body would otherwise paint into. 40px is a measured
              // floor: enough to cover the .caption font + 8pt bottom
              // padding the strip uses in ReaderChromeView, with a
              // little air. TODO: move to Advanced Settings when the
              // settings screen ships (Overall Directive §10).
              var CHROME_BOTTOM_RESERVE = 40;
              padBottom = Math.max(padBottom, CHROME_BOTTOM_RESERVE);

              // Same idea at the top: reserve enough room for the
              // chrome's action bar (close button, title, Aa) so the
              // first line of body text doesn't sit under it when
              // chrome is revealed. 60px covers the action bar's 44pt
              // tap targets + 4pt top padding + a typical iPad
              // landscape status-bar inset. iPhone with a notch may
              // want more — revisit if the cover image / first line
              // of chapter text looks cropped on iPhone testing.
              var CHROME_TOP_RESERVE = 60;
              padTop = Math.max(padTop, CHROME_TOP_RESERVE);

              setI(html, 'height', window.innerHeight + 'px');
              setI(html, 'overflow-x', 'hidden');
              setI(html, 'overflow-y', 'hidden');
              setI(html, 'margin', '0');

              setI(body, 'margin', '0');
              // box-sizing border-box so body's box width INCLUDES
              // padding, which means box width === innerWidth and the
              // column step (column-width + column-gap) equals
              // innerWidth exactly.
              setI(body, 'box-sizing', 'border-box');
              setI(body, 'width', window.innerWidth + 'px');
              setI(body, 'height', window.innerHeight + 'px');
              setI(body, 'padding-top',    padTop    + 'px');
              setI(body, 'padding-right',  padRight  + 'px');
              setI(body, 'padding-bottom', padBottom + 'px');
              setI(body, 'padding-left',   padLeft   + 'px');

              // Column geometry that lines up with translate-by-
              // innerWidth. Earlier this code used
              //   column-width: 100vw; column-gap: 0;
              // while CSSBuilder injected a body-padding of ~20pt for
              // the user margin. The browser then sized each column at
              // (100vw − 40pt) wide because of the padding, but the
              // page-turn translate still moved by 100vw — which left
              // every page mis-aligned by ~40pt and made the right edge
              // of each page show a sliver of the NEXT page's content.
              // (The user-visible symptom was "the right side of the
              // page is a mess of two sub-columns and tiny text",
              // because the next column's first words were jammed in
              // beside the current one.)
              //
              // The fix: shrink column-width by the same horizontal
              // padding, and put the difference into column-gap. Now:
              //   column-width + column-gap === innerWidth
              // so a translate of -(n-1)*innerWidth lands page n
              // exactly. Column-gap also gives a built-in visual margin
              // between columns, so each page has user-margin space on
              // both left and right (column 1 gets its left margin from
              // body padding-left, column 1's right margin and column
              // 2's left margin together come from column-gap, etc.).
              var horizPad = padLeft + padRight;
              setI(body, 'column-width', (window.innerWidth - horizPad) + 'px');
              setI(body, 'column-gap',   horizPad + 'px');
              setI(body, 'column-fill',  'auto');
              setI(body, '-webkit-column-width', (window.innerWidth - horizPad) + 'px');
              setI(body, '-webkit-column-gap',   horizPad + 'px');
              setI(body, '-webkit-column-fill',  'auto');

              // body MUST keep overflow: visible. With column-width +
              // column-fill: auto, columns 2..N live in body's
              // horizontal-overflow region (column 1 sits in body's box;
              // column 2 starts at +innerWidth, column 3 at +2*innerWidth,
              // etc.). The page-turn translate below moves body left by
              // -(n-1)*innerWidth so column n lands inside the html
              // viewport. If body has overflow: hidden it clips columns
              // 2..N at its own edge BEFORE the translate is applied —
              // so pages 2+ render blank even though `currentPage` and
              // the translateX value are correct. (This was the bug
              // captured in HANDOFF §2.1.C: total=3 reported, snap lands
              // on the right VC, but later pages show empty.) The
              // visible viewport is clipped by `html { overflow: hidden }`
              // above; body must NOT double-clip.
              setI(body, 'overflow-x', 'visible');
              setI(body, 'overflow-y', 'visible');
              setI(body, 'max-width', 'none');
              // No CSS transition — UIPageViewController handles the
              // visible page-turn animation; a transition here would
              // fight it.
            } else {
              body.style.removeProperty('transform');
              body.style.removeProperty('column-width');
              body.style.removeProperty('column-gap');
              body.style.removeProperty('column-fill');
              body.style.removeProperty('-webkit-column-width');
              body.style.removeProperty('-webkit-column-gap');
              body.style.removeProperty('-webkit-column-fill');
            }
          }

          var currentPage = 1;
          var totalPages = 1;

          function measure() {
            if (PAGINATED) {
              var pageWidth = Math.max(1, window.innerWidth);
              var totalWidth = document.body.scrollWidth;
              totalPages = Math.max(1, Math.round(totalWidth / pageWidth));
              currentPage = Math.min(currentPage, totalPages);
              translateToPage(currentPage);
            } else {
              totalPages = 1;
              currentPage = 1;
            }
            post({ type: 'pagination',
                   totalPages: totalPages,
                   currentPage: currentPage,
                   paginated: PAGINATED });
          }

          function translateToPage(n) {
            if (!PAGINATED) return;
            var idx = Math.max(0, Math.min(n - 1, totalPages - 1));
            document.body.style.transform =
              'translateX(' + (-idx * window.innerWidth) + 'px)';
          }

          function post(payload) {
            try {
              window.webkit.messageHandlers.\(messageHandlerName)
                    .postMessage(payload);
            } catch (e) { /* no-op if handler isn't attached */ }
          }

          // Swift-callable API.
          window.codexGoToPage = function(n) {
            currentPage = Math.max(1, Math.min(n, totalPages));
            translateToPage(currentPage);
            post({ type: 'pageChanged', currentPage: currentPage });
          };
          window.codexSnapToPage = function(n) {
            // Initial lock — no pageChanged post.
            //
            // OUT-OF-RANGE GUARD:
            // A page-VC is sometimes created for a pageIndex that
            // doesn't exist in this chapter — most commonly the
            // right-hand page of an iPad-landscape Page Curl spread
            // when the current chapter has fewer pages than the spread
            // requires. Without this guard, snap would clamp the
            // request to the chapter's last column and show a visible
            // DUPLICATE of the left page. We hide the body instead.
            // The Swift coordinator detects the same condition (via
            // the pagination message that triggered this snap) and
            // may replace this VC with a cross-chapter page; until
            // that swap lands the user sees blank, not duplicate.
            if (PAGINATED && n > totalPages) {
              if (document.body) {
                document.body.style.setProperty(
                  'visibility', 'hidden', 'important');
              }
              return;
            }
            if (PAGINATED && document.body) {
              document.body.style.removeProperty('visibility');
            }
            currentPage = Math.max(1, Math.min(n, totalPages));
            translateToPage(currentPage);
          };
          window.codexScrollProgress = function() {
            var h = Math.max(1, document.documentElement.scrollHeight
                              - window.innerHeight);
            return Math.max(0, Math.min(1, window.scrollY / h));
          };

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
              applyLayout();
              requestAnimationFrame(measure);
            });
          } else {
            applyLayout();
            requestAnimationFrame(measure);
          }

          var resizeTimer = null;
          window.addEventListener('resize', function() {
            if (resizeTimer) clearTimeout(resizeTimer);
            resizeTimer = setTimeout(function() {
              applyLayout();
              measure();
            }, 50);
          });

          window.addEventListener('scroll', function() {
            if (PAGINATED) return;
            post({ type: 'scrollProgress',
                   progress: window.codexScrollProgress() });
          }, { passive: true });
        })();
        """
    }
}
