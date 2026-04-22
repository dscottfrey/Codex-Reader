---
name: Page Curl implementation — UIPageViewController, no third-party libs
description: Codex Reader — Scott has resolved the Page Curl implementation question. Use UIPageViewController(.pageCurl) wrapped in UIViewControllerRepresentable. Ship it as v1 scope.
type: project
originSessionId: b89b30db-30e8-4c38-bf72-44d09a12be26
---
Page Curl page turn style (Rendering Engine §2.5) is a deal-breaker requirement for Codex Reader — it's one of the core reading experiences that differentiates a book-feel reader from a text viewer.

**Implementation decision (2026-04-22, Scott's research):** Use `UIPageViewController` with `transitionStyle: .pageCurl`, wrapped in a `UIViewControllerRepresentable`. Per Scott: this is a public Apple API, not deprecated, available since iOS 5 and confirmed working on iOS 17+. Do not use any third-party library.

Per §2.5, **Slide** uses the same `UIPageViewController` architecture with `transitionStyle: .scroll` — so the Curl and Slide implementations share a wrapper. Scroll mode stays on a plain WKWebView with its native vertical scroll.

**How to apply:**
- A single `UIPageViewController` wrapper drives both Curl and Slide. The transition style switches based on the user's setting.
- Each "page" view controller in the UIPageViewController owns its own thin WKWebView configured to display exactly one column of the current chapter. UIPageViewController keeps ~3 page VCs alive at once (current, prev, next), so the memory budget matches §5 ("no more than 3 chapter WKWebView instances in memory at once"). The earlier "N WebViews per chapter" concern was mistaken — that was the per-VC count, not the keep-alive count.
- The CSS-transform slide implementation in PaginationJS.swift (which pre-dates this decision) is a bridge — it gets replaced when the UIPageViewController wrapper lands.
- When adding or modifying page-turn code, treat §2.5 as authoritative on the architecture: UIPageViewController for Curl+Slide, WKWebView native for Scroll.

**Don't:** reach for a third-party library, re-introduce the "defer Curl" position, or try to share one WKWebView across the page-VC children — that's the direction that forces snapshot images and breaks live text selection during transitions.
