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
              setI(html, 'height', window.innerHeight + 'px');
              setI(html, 'overflow-x', 'hidden');
              setI(html, 'overflow-y', 'hidden');
              setI(html, 'margin', '0');

              setI(body, 'margin', '0');
              setI(body, 'height', window.innerHeight + 'px');
              setI(body, 'column-width', window.innerWidth + 'px');
              setI(body, 'column-gap', '0px');
              setI(body, 'column-fill', 'auto');
              setI(body, '-webkit-column-width', window.innerWidth + 'px');
              setI(body, '-webkit-column-gap', '0px');
              setI(body, '-webkit-column-fill', 'auto');
              setI(body, 'overflow', 'hidden');
              setI(body, 'width', 'auto');
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
