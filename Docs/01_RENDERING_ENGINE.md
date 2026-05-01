# Codex — Module 1: Rendering Engine Directive

**Module:** Rendering Engine  
**Priority:** Critical — this is the core of the app  
**Dependencies:** None (all other modules depend on this one)

---

## 1. Purpose

The Rendering Engine is responsible for parsing an epub file and displaying its content to the user in a readable, fully customizable format. It is the single most important module in Codex and the primary reason the app exists: Apple Books' rendering engine is restrictive and opinionated in ways that frustrate readers. Codex's rendering engine is built on the opposite philosophy — the user controls everything.

---

## 2. Core Requirements

### 2.1 Global Preferences Are Always the Baseline

The user's typography settings are **always applied**, regardless of how the epub is encoded. The epub file's embedded font declarations, size declarations, margin rules, and line spacing are completely overridden by the user's preferences. The epub's encoding is not used as a starting point, a suggestion, or a fallback. It is irrelevant.

This is the foundational design principle of the Rendering Engine and the primary reason Codex exists. Apple Books applies its own caps and overrides the user's preferences with the epub's encoding at arbitrary thresholds. Codex does not.

**The two-tier settings model:**

| Tier | What it is | Scope |
|---|---|---|
| **Global preferences** (`ReaderSettings`) | The user's personal defaults — font, size, margins, leading, etc. Always applied to every book. | All books |
| **Per-book overrides** (`BookReaderOverrides`) | Optional adjustments the user makes for a specific book, on top of their global preferences. Stored with the book. | One book |

When Codex opens a book for the first time, a **typography choice prompt** (§4.6) offers the user three options: use the publisher's encoded style, apply their own defaults, or customise. The choice is stored permanently and determines how CSS injection works for that book from that point on. See §4.6 for the full prompt specification and §7 for the data model.

When Codex opens a book after the first time, it uses the stored `typographyMode` to determine what to inject. The three modes and how they work are specified in §7.

### 2.2 Font Size — Unconstrained by Default, User-Configurable Range

- The font size slider spans an intentionally wide range: **8pt minimum to 72pt maximum** as the out-of-the-box defaults.
- There is no hardcoded ceiling or floor baked into the app. These are user-configurable values in Advanced Settings (§4.5), defaulting to 8pt and 72pt. The user can widen or tighten this range to their preference.
- The epub's own font-size declarations are ignored in user-defaults and custom modes; the user's chosen size (or the effective merged size) always wins.
- **Publisher mode safety floor:** when rendering in `.publisherDefault` mode, a separate minimum floor (default 10pt, Advanced Settings) prevents genuinely broken epub CSS from producing illegible text. This floor is independent of the user's personal range setting and applies only in publisher mode.
- Implementation: `font-size` set on `html`, `body`, and common content tags using `!important`.

### 2.3 Margins — Independently Adjustable

- The user can set left, right, top, and bottom margins independently.
- Default margins should be comfortable (approx. 20pt on all sides) but this is a global preference the user should adjust to their taste.
- Margin adjustments are applied via CSS injection (`padding` or `margin` on the `body` element).

### 2.4 Font Family — Full Override

- The user can select a font family that applies to all body text in the epub.
- Font options should include:
  - System fonts available on iOS (e.g., San Francisco, New York, Georgia, Palatino, Helvetica Neue, Times New Roman)
  - Optionally: user-installed custom fonts via the iOS font management system
- The epub's embedded or referenced fonts are overridden via CSS injection (`font-family: '[UserFont]' !important` on `body` and content elements).
- The user may also choose "Use book fonts" to allow the epub's own typography — this should be the non-default option, since most users open Settings because they want to override.

### 2.5 Page Turn Style — User-Selected, Never Auto-Switched

The user selects a page turn style in Settings. All three styles operate on pre-rendered UIImages (see §3.3). The display layer is always a UIImageView; the page turn mechanism animates between UIImageViews. No live WKWebView content is involved during a page turn gesture.

| Style | Description | Implementation |
|---|---|---|
| **Page Curl** | Skeuomorphic paper curl. The page peels back revealing the next page beneath, with a realistic curl shadow. The curl physically follows the user's finger. | `UIPageViewController` with `transitionStyle: .pageCurl`. Each page is a lightweight `UIViewController` containing a `UIImageView` showing the pre-rendered page image. UIPageViewController snapshots these lightweight views — fast and smooth because the content is already a UIImage, not a live WebView. |
| **Slide / Swipe** | Page follows the user's finger horizontally; release past the midpoint completes the turn. | `UIPageViewController` with `transitionStyle: .scroll`. Same UIImageView page controllers. |
| **Scroll** | Continuous vertical scroll through the chapter. No page breaks. | A single `UIScrollView` containing a `UIImageView` per page, arranged vertically. Or a WKWebView in scroll mode for this specific case — see §3.4. |

Fade was considered and dropped. It requires hand-rolled animation code and adds no reading value.

**Implementation note on Page Curl:** `UIPageViewController` with `.pageCurl` is a public UIKit API, confirmed non-deprecated and available on iOS 17+. It is not a private API. SwiftUI integration is via `UIViewControllerRepresentable`. Because each page controller contains only a UIImageView (pre-rendered content), the snapshot UIPageViewController takes at gesture start is always sharp and instantaneous — there is no live WebView to wait for. Pre-loading is still required (see §3.3) to ensure adjacent page images are in the cache before the user's finger arrives.

**Page Curl gesture behaviour — specific requirements:**

- **Drag only.** Page turns in Curl mode are initiated exclusively by a drag/swipe gesture. Taps do NOT turn pages. The tap gesture recogniser on `UIPageViewController` must be disabled. Taps are reserved for toggling reader chrome (System 1, §4.1). **Implementation order:** confirm page curl is working correctly before disabling the tap recogniser.

- **The back of the curling page shows the next page.** The underside of the curl shows a dimmed preview of the next page — not a blank surface. Because page controllers contain UIImageViews (not live WebViews), the next page's UIImageView is trivially available for UIPageViewController to snapshot. This is the default `.pageCurl` behaviour and must be preserved.

- **Post-v1: custom Metal curl.** The UIPageViewController curl is good. A custom Metal implementation would allow more physically accurate curl physics, precise lighting on the curved surface, and a crease that follows the finger exactly. The pre-rendered UIImage architecture makes this migration natural — the image content is already available as a texture. This is not a v1 concern.

**Anti-requirement:** Apple Books switches from Page Curl to Slide when font size exceeds a certain threshold. Codex must never do this. The selected style is locked until the user changes it in Settings. The only exception is the orientation-triggered auto-switch described in §2.6.

**Scroll mode note:** Scroll mode changes the fundamental reading metaphor — there are no "pages." The bottom bar shows a percentage bar rather than "Page N of M." Chapter transitions happen automatically when the user scrolls past the end of the current chapter. In scroll mode, the pre-render-to-UIImage architecture may be relaxed — the WKWebView can render live in scroll mode since there is no page-turn animation requiring pre-baked images. This is a decision for the implementation phase.

### 2.6 Orientation and Auto-Switch to Scroll

Rotating an iPad to portrait orientation while reading is a deliberate gesture — most commonly used to switch the reading surface to continuous scroll for text selection across what would otherwise be a page boundary. In Apple Books, selecting text that starts on a right-hand page and ends on a left-hand page requires approximately seven taps. In Codex, the user rotates the device and selects in one gesture.

**Auto-switch behaviour:**

| Situation | Behaviour |
|---|---|
| iPad, reading in landscape (Curl or Slide), user rotates to portrait | Auto-switch to Scroll mode. Saves the previous style. |
| iPad, device already in portrait when book opens | Do not auto-switch. Respect chosen page turn style. |
| iPad, user rotates back to landscape | Restore the previously saved page turn style. |
| iPhone, any rotation | No auto-switch. |

The auto-switch is triggered by the act of rotation, not the resulting orientation.

**Sensible defaults** (pending user research validation):
- iPad: rotation enabled, auto-switch on
- iPhone: rotation locked to portrait, no auto-switch

Both are configurable in Settings → Reading → Orientation (see §4.5).

**Per-book override:** orientation settings can be overridden per-book via `BookReaderOverrides`.

### 2.7 Pagination — CSS Columns

Pagination uses **CSS multi-column layout**, not JavaScript scroll-position estimation.

**Why CSS Columns:** After a WKWebView loads a chapter and CSS is applied, JavaScript measuring `scrollHeight` to estimate page count is fragile — fonts swapping late, images loading asynchronously, and dynamic content can all change content height after measurement. CSS Columns hands pagination to the browser's layout engine: the browser divides the chapter into columns of exactly `[viewport-width]` × `[viewport-height]` pixels. Page count is `scrollWidth ÷ columnWidth` — an integer the browser provides, not a JavaScript estimate. Page boundaries are deterministic and stable.

**CSS Columns implementation:**

```css
/* Injected alongside user typography CSS, after layout dimensions are known */
html {
    width:  [VIEWPORT_WIDTH]px;
    height: [VIEWPORT_HEIGHT]px;
    overflow: hidden;
}
body {
    columns: 1;
    column-width: [VIEWPORT_WIDTH]px;
    column-gap: 0px;
    height: [VIEWPORT_HEIGHT]px;
    overflow: hidden;
    /* margins applied via padding on body, not as margin (margin collapses columns) */
    padding: [TOP]px [RIGHT]px [BOTTOM]px [LEFT]px !important;
}
```

**Getting page count and snapshotting:**

```javascript
// Called after CSS Columns injection and layout settles.
// Returns the total number of pages (columns) in this chapter.
function getPageCount() {
    return Math.round(document.body.scrollWidth / window.innerWidth);
}

// Translate to page N (zero-indexed).
// The WebView's content is a horizontal strip of columns; we translate left.
function goToPage(index) {
    document.body.style.transform = `translateX(-${index * window.innerWidth}px)`;
    document.body.style.webkitTransform = `translateX(-${index * window.innerWidth}px)`;
}
```

After calling `goToPage(n)`, the WebView is snapshotted (see §3.3). The snapshot is the UIImage for page `n`. No layout re-calculation is needed between pages — the columns are already laid out; you simply translate to reveal each one.

**Known CSS Columns edge cases** (handle during implementation, document fixes):
- Elements with `position: absolute` or `position: fixed` may not column-flow correctly. Apply `position: relative !important` to known offenders.
- Tables and wide images may overflow a single column. `max-width: 100% !important` on `img, table` prevents this.
- Chapter-opening blank pages sometimes appear due to epub CSS margins pushing content to column 2. Detect and skip empty leading columns (all-white or below a pixel variance threshold).
- Some epub CSS fights the column layout with explicit `width` or `overflow` declarations on `body` or `html`. These must be overridden in the column injection CSS.

Document every workaround added here with a comment explaining the epub pattern it fixes, per the "Document the Journey" principle in `00_OVERALL_DIRECTIVE.md §6.2`.

### 2.8 Additional Typography Controls

| Setting | Range / Options | Default |
|---|---|---|
| Line spacing | 1.0× to 2.5× (in 0.1× steps) | 1.4× |
| Paragraph spacing | 0em to 2.0em (in 0.1em steps) | 0.8em |
| Letter spacing | -2px to +4px | 0px |
| Text alignment | Left, Justified | Left |
| Theme | Light, Dark, Sepia (see §2.10) | Follows system (see §2.10) |

**Paragraph spacing note:** Epub CSS varies widely — many publishers do not specify paragraph spacing, and some explicitly set it to zero, using first-line indent as the paragraph separator instead. Codex always injects a paragraph spacing value regardless of what the epub specifies. The default of 0.8em provides comfortable visual separation without looking like a web page. The injected CSS targets `p` elements with `margin-bottom` — see §3.2 for the full CSS injection spec.

### 2.9 Skeuomorphic Reader Surface

The reading surface has several independent skeuomorphic options. All are off by default. Each element can be enabled individually in Settings → Reading → Reader Appearance.

**Implementation note:** paper grain, warmth, and shadow are applied as **Core Image post-processing on the pre-rendered UIImage**, not as CSS injection into the WKWebView. This means they are zero-cost to change — they do not require a WkWebView re-render, only a Core Image filter pass on the already-cached page image. The filter chain is fast on modern hardware and produces the final composite UIImage shown in the UIImageView.

#### Paper Surface

A subtle, low-contrast paper grain texture applied over the reading background.

- Available in Light and Sepia themes only; forced off in Dark theme.
- When Paper is active and the page turn style is Page Curl or Slide, a faint drop shadow beneath the page gives the impression the page is resting above a surface.
- The texture is a high-quality, licence-free static image tile bundled with the app.
- **Implementation:** `CIFilter` multiply blend of the grain tile over the base page image. The grain tile is loaded once and reused across all pages.

#### Page Stack Edges

The trailing edge of the reading area shows a thin strip of fanned, layered page edges.

- The apparent thickness of the stack scales with remaining reading progress.
- Rendered as a custom decorative view layered outside the page image area. Does not affect page image content.
- Available in Page Curl and Slide turn styles only.

#### Spine and Gutter

**v1 — leading-edge binding shadow:** a narrow vertical gradient along the leading edge of the reading area, applied as a Core Image gradient composite over the page image.

**Post-v1 — centre spine (two-column iPad landscape):** deferred. Setting reserved in data model.

### 2.10 Theme and Dark Mode Detection

The user's reading theme (Light / Dark / Sepia) is set in the reader settings panel (§4.2). Theme affects:

1. **The CSS injected into the WKWebView** — background and text colour for the off-screen render.
2. **The Core Image filter chain** — sepia tone, warmth adjustments applied as post-processing.

Codex offers five modes for determining the active theme, configurable in Settings → Reading → Theme:

| Mode | Behaviour |
|---|---|
| **Follow System** (default) | Light when iOS is Light; Dark when iOS is Dark. |
| **Always Light** | Stays in Light regardless of system appearance. |
| **Always Dark** | Stays in Dark regardless of system appearance. |
| **Always Sepia** | Stays in Sepia regardless of system appearance. |
| **Scheduled** | User sets time-of-day transitions. |
| **Match Surroundings** | Switches to Dark when ambient light drops below threshold. See below. |

**Per-book theme override:** theme is part of `BookReaderOverrides` (§7.3).

**Follow-system implementation:** detected via `UITraitCollection.userInterfaceStyle`. A theme change invalidates the page image cache for the current chapter and triggers a re-render.

#### Match Surroundings — Ambient Light Detection

iOS does not expose the ambient light sensor to third-party apps. Two legitimate workarounds:

- **UIScreen brightness proxy:** monitor `UIScreen.main.brightness` for unprompted drops. No special permissions required. Imperfect — won't fire if auto-brightness is disabled.
- **Front camera sampling:** more accurate, requires camera permission. Likely not the right path for a reading app.

**Recommendation:** implement the brightness-proxy approach for v1, labelled "Matches surroundings (requires auto-brightness)" in Settings.

The threshold (brightness level at which Dark activates) is configurable in Advanced Settings — default 30%.

#### Background Warmth — True Tone Independence

A **Background Warmth** slider in the reader settings panel applies a warm-to-cool colour tint to the reading background, independent of the system True Tone setting.

- At the centre position (default): background is the theme's native colour.
- Sliding warmer: shifts toward amber/cream.
- Sliding cooler: shifts toward blue-white.

**Implementation:** a `CIColorMatrix` filter applied to the pre-rendered page image as part of the Core Image compositing pass. Adjusting the warmth slider does not require a WKWebView re-render — it is a post-processing parameter change that produces a new composite UIImage instantly.

---

## 3. Epub Rendering Architecture

### 3.1 The Pipeline — Overview

The Rendering Engine is structured as a pipeline with three distinct stages. Understanding this separation is essential for implementation.

```
┌─────────────────────────────────────────────────────┐
│  STAGE 1: CONTENT BAKING                            │
│  R2Streamer → WKWebView (off-screen)                │
│  Epub parsed, content served via localhost HTTP.    │
│  CSS Columns injected. Chapter paginated.           │
│  Each page snapshotted → UIImage (base texture).   │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE 2: GPU COMPOSITING                           │
│  Core Image filter chain                            │
│  Base texture + highlights + grain + warmth +      │
│  shadow → final composite UIImage                  │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE 3: DISPLAY + INTERACTION                     │
│  UIImageView in UIPageViewController                │
│  Shows final composite. Page curl/slide operates   │
│  on UIImageViews — lightweight, smooth.             │
│                                                     │
│  WKWebView interaction layer sits behind UIImageView│
│  for text selection and find-in-page.              │
└─────────────────────────────────────────────────────┘
```

The WKWebView is a **content baker**, not a display surface. It renders once per page, into a UIImage. After that, it is not involved in what the user sees. All visual composition and animation happens downstream of that bake.

This architecture was chosen because:
- Page curl animation operates on UIImages (lightweight, instant snapshots)
- Visual effects (highlights, grain, warmth) are GPU post-processing operations, not CSS re-renders
- Text selection uses the always-present WKWebView interaction layer — no OCR or position reconstruction needed
- The architecture scales naturally toward a custom Metal curl in a later version

### 3.2 Stage 1: Epub Loading — Readium Swift Toolkit

✅ **Decided (reader path): Readium Swift Toolkit pinned at 3.8.0.**
⚠️ **Scoping (this branch): only the *reader* uses Readium. `IngestionPipeline` continues to use the legacy custom `EpubParser` for metadata + cover extraction at ingest time.** Migration plan documented in `CLAUDE.md` handoff notes ("Ingestion still on the custom epub parser"). Trigger to migrate ingestion: the first epub that ingests poorly with the custom parser.

**Why Readium:** The custom parser approach (unzip + XMLParser) handles simple epubs but accumulates workarounds for malformed files, unusual spine structures, epub 3 edge cases, and fixed-layout formats. Readium is a mature, production-tested library used in major epub readers. Its primary benefits for Codex are: (1) robust epub 2 and epub 3 parsing including edge cases we would otherwise fix one by one; (2) a **local HTTP server** that serves epub content to the WKWebView, which correctly resolves relative resource paths (images, fonts, CSS inside the epub ZIP) without the workarounds that `loadFileURL(allowingReadAccessTo:)` requires. Its features beyond parsing and serving (Readium's Navigator rendering pipeline and pagination) are explicitly not used — Codex implements its own rendering pipeline.

**Dependency declaration:** Readium is added via Swift Package Manager. Three products are imported.

```
Package URL:  https://github.com/readium/swift-toolkit.git
Pinned at:    exact version 3.8.0 (March 2026)
iOS minimum:  15.0 (Codex targets 17+, so this is non-binding)

Imported products:
  • ReadiumShared              — core models (Publication, Link, URLs, Resource)
  • ReadiumStreamer            — AssetRetriever, PublicationOpener, DefaultPublicationParser
  • ReadiumAdapterGCDWebServer — GCDHTTPServer (deprecated, see below)

NOT imported:
  • ReadiumNavigator — Codex implements its own rendering pipeline
  • ReadiumOPDS / ReadiumLCP — out of scope for the current branch
```

**⚠️ GCDHTTPServer is deprecated.** Readium 3.8.0 marks `GCDHTTPServer` as `@available(*, deprecated, message: "The Readium navigators do not need an HTTP server anymore. This adapter will be removed in a future version of the toolkit.")`. Readium's own EPUBNavigator has moved to a `WKURLSchemeHandler` against a custom `readium://` scheme — Readium does not export that handler as public API.

We are using the deprecated server anyway because: (1) localhost URLs drop into existing `WKWebView.load(URLRequest:)` call sites unchanged (~5 LOC of integration); (2) the alternative is ~50–80 LOC of custom URL-scheme-handler code that doesn't earn its keep for a proof-of-concept. When Readium removes `GCDHTTPServer`, we migrate (see `CLAUDE.md` handoff note "Readium GCDHTTPServer is deprecated"). The migration is contained in `EpubLoader.swift` and the WKWebView config — `ParsedEpub.SpineItem.absoluteURL` stays a `URL`, just with a different scheme.

**Integration:**

Readium provides a `Publication` object and a local HTTP server. Codex wraps these behind a thin adapter so the rest of the app does not depend on Readium types directly. The adapter lives in `Codex Reader/EpubLoader/EpubLoader.swift` and exposes the same `ParsedEpub` struct the rest of the codebase already uses (defined in `Codex Reader/EpubParser/ParsedEpub.swift`, kept for now since ingestion still consumes it).

```swift
// EpubLoader/EpubLoader.swift
//
// Thin wrapper around Readium. The rest of the app uses ParsedEpub —
// not Readium's Publication type directly. This isolates the dependency
// and makes a future streamer swap (or scheme-handler migration)
// possible without touching other modules.

import ReadiumShared
import ReadiumStreamer
import ReadiumAdapterGCDWebServer

@MainActor
final class EpubLoader {
    private let assetRetriever: AssetRetriever
    private let publicationOpener: PublicationOpener
    private var server: GCDHTTPServer?
    private var publication: Publication?

    init() {
        let httpClient = DefaultHTTPClient()
        self.assetRetriever = AssetRetriever(httpClient: httpClient)
        self.publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
    }

    /// Open the epub, start the HTTP server, return a ParsedEpub
    /// whose SpineItem.absoluteURL fields are localhost URLs.
    func open(_ epubFileURL: URL) async throws -> ParsedEpub {
        guard let absoluteURL = AnyURL(url: epubFileURL).absoluteURL else {
            throw EpubLoaderError.invalidURL(epubFileURL)
        }

        let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
        let pub   = try await publicationOpener.open(
            asset: asset,
            allowUserInteraction: false
        ).get()

        let server = GCDHTTPServer(assetRetriever: assetRetriever)
        let baseURL: HTTPURL = try server.serve(
            at: "codex/\(UUID().uuidString.lowercased())",
            publication: pub
        )

        self.server = server
        self.publication = pub
        return makeParsedEpub(from: pub, baseURL: baseURL)
    }

    func close() {
        server = nil      // GCDHTTPServer stops on dealloc
        publication = nil
    }
}
```

**Resolving spine hrefs to localhost URLs:**

```swift
// Each Link's href is a relative URL string (e.g. "EPUB/text/chap01.xhtml").
// Standard URL relative-resolution against the server's base URL gives the
// full localhost URL the WKWebView loads.
func resolveChapterURL(href: String, baseURL: HTTPURL) -> URL? {
    URL(string: href, relativeTo: baseURL.url)?.absoluteURL
}
```

**The ParsedEpub fields the reader cares about:**

| Field | Source | Notes |
|---|---|---|
| `title`, `author`, `language` | `pub.metadata.{title, authors, languages}` | Authors joined with ", " |
| `spine: [SpineItem]` | `pub.readingOrder` | Each Link → SpineItem with localhost `absoluteURL` |
| `tocEntries: [TocEntry]` | `await pub.tableOfContents()` | Recursive on `link.children` |
| `coverImageURL` | (unused by reader) | nil; ingestion path still extracts via custom EpubParser |
| `manifestItems` | (unused by reader) | empty; not needed once spine is resolved |
| `unzippedRoot` | (unused by reader) | set to `baseURL.url` so any consumer reading it gets a non-nil URL |

**Loading chapters into WKWebView — scheme-aware helper:**

A small helper picks the right WebKit API based on the URL's scheme. File URLs (the legacy custom-parser path, still used by ingestion) need `loadFileURL(_:allowingReadAccessTo:)`; HTTP URLs (the Readium-served path) need `load(URLRequest:)`.

```swift
// Rendering/WKWebView+ChapterLoad.swift
extension WKWebView {
    func loadChapter(at url: URL, readAccess: URL?) {
        if url.isFileURL {
            loadFileURL(url, allowingReadAccessTo: readAccess ?? url.deletingLastPathComponent())
        } else {
            load(URLRequest(url: url))
        }
    }
}
```

`ChapterPageVC` and `WKWebViewWrapper` both call `loadChapter(at:readAccess:)`. The day the legacy custom parser is deleted, the helper collapses to a single `load(URLRequest:)` call.

**What Readium handles that the custom parser did not:**

- Epub 2 and epub 3 spine and manifest parsing, including edge cases
- Malformed container.xml and OPF with graceful recovery
- Fixed-layout epub detection (via `Publication.metadata.presentation.layout`)
- Epub resources (images, fonts, CSS) served correctly to the WebView via HTTP — no cross-origin or file-access workarounds needed
- Correct relative URL resolution within the epub ZIP

**What Readium does NOT do in this architecture:**

- Render anything. Rendering is entirely Codex's WKWebView + CSS Columns pipeline.
- Paginate. Pagination is CSS Columns (§2.7).
- Manage reading position. That is SwiftData + the Sync Engine.
- Provide any UI. ReadiumNavigator is not used.

### 3.3 Stage 1: CSS Injection and Page Snapshotting

The off-screen WKWebView is configured at setup and serves as a rendering tool. It is never displayed directly to the user.

**Off-screen WKWebView setup:**

```swift
// A WKWebView used purely for rendering. Not in the view hierarchy.
// Sized to the reading area dimensions (viewport minus safe area insets).
// R2Streamer's local HTTP server handles resource loading — no special
// allowingReadAccessTo URL needed; standard WKWebView URL loading works.
let renderWebView = WKWebView(frame: CGRect(origin: .zero, size: readingAreaSize))
// Not added to any view — lives off-screen
```

**Chapter load and CSS injection sequence:**

```
1. Load chapter via R2Streamer URL:
   renderWebView.load(URLRequest(url: spineItem.chapterURL))

2. On webView(_:didFinish:):
   a. Inject user typography CSS (font, size, margins, alignment, etc.)
      — WKUserScript at document end, or evaluateJavaScript
   b. Inject CSS Columns layout CSS (§2.7)
   c. Wait one runloop tick for layout to settle
   d. Query page count: evaluateJavaScript("getPageCount()") → Int
   e. For each page index 0..<pageCount:
      i.  evaluateJavaScript("goToPage(\(index))")
      ii. Wait one runloop tick
      iii. Snapshot: renderWebView.takeSnapshot(with:) → UIImage
      iv. Pass UIImage to Stage 2 (Core Image compositing)
      v.  Store final composite UIImage in page cache
```

**The CSS being injected (typography):**

```css
html, body, p, div, span, li, td, th {
    font-size: {{USER_FONT_SIZE}}px !important;
    font-family: '{{USER_FONT_FAMILY}}', serif !important;
    line-height: {{USER_LINE_SPACING}} !important;
    letter-spacing: {{USER_LETTER_SPACING}}px !important;
    text-align: {{USER_TEXT_ALIGNMENT}} !important;
}
body {
    background-color: {{THEME_BG}} !important;
    color: {{THEME_TEXT}} !important;
}
p {
    margin-bottom: {{USER_PARAGRAPH_SPACING}}em !important;
}
img, table {
    max-width: 100% !important;
}
```

**CSS Columns layout CSS** (injected after typography, once dimensions are known):

```css
html {
    width:  {{VIEWPORT_WIDTH}}px  !important;
    height: {{VIEWPORT_HEIGHT}}px !important;
    overflow: hidden !important;
}
body {
    columns: 1 !important;
    column-width: {{VIEWPORT_WIDTH}}px !important;
    column-gap: 0px !important;
    height: {{VIEWPORT_HEIGHT}}px !important;
    overflow: hidden !important;
    margin: 0 !important;
    padding: {{TOP}}px {{RIGHT}}px {{BOTTOM}}px {{LEFT}}px !important;
    /* Note: margins applied as padding on body. CSS Columns and margin interact
       poorly — padding avoids column-break issues at margin boundaries. */
}
```

**Theme colour values:**

| Theme | Background (`{{THEME_BG}}`) | Text (`{{THEME_TEXT}}`) |
|---|---|---|
| Light | `#FFFFFF` | `#1C1C1E` |
| Dark | `#1C1C1E` | `#F2F2F7` |
| Sepia | `#F5EDD6` | `#3B2A1A` |

These are constants in `ReaderTheme.swift`, not hardcoded in injection strings.

**When settings change:**

When the user adjusts a typography setting in the reader panel, all cached page images for the current chapter are invalidated. The off-screen WKWebView re-renders the chapter from the current page position outward (current page first, then adjacent pages, then the rest of the chapter). The updated composite UIImage replaces the stale UIImage in the display layer without a visible page reload — the UIImageView simply receives a new image.

**Pre-rendering during idle time:**

While the user is reading page N, the pre-render pipeline runs in the background:
- Pages N+1 and N+2 of the current chapter (highest priority)
- Page 1 of the next chapter (so chapter transitions are ready)
- Pages N-1 and N-2 (for backwards navigation)

The pre-render pipeline runs on a background thread, posting completed UIImages to the main thread for cache storage. It yields to user interaction — if the user turns a page before the next image is ready, the display falls back to a brief loading state (acceptable; should be rare on modern hardware).

**Snapshot API:**

```swift
// WKWebView.takeSnapshot(with:completionHandler:) — public API, iOS 11+
// Captures exactly what the WebView is rendering at this moment.
// Because the WebView is already positioned at column N via goToPage(),
// the snapshot captures exactly the right content.
let config = WKSnapshotConfiguration()
config.rect = CGRect(origin: .zero, size: readingAreaSize)
renderWebView.takeSnapshot(with: config) { image, error in
    guard let image, error == nil else { return }
    // image is the base texture for this page — pass to Stage 2
    self.compositeAndCache(baseImage: image, pageIndex: index, chapterId: chapterId)
}
```

### 3.4 Stage 2: Core Image Compositing

Every page is composited from its base texture plus any additional layers before being shown in the display layer. This compositing happens on the GPU via Core Image and is fast enough that it is invisible to the user.

**Compositing layers (applied in order):**

```
1. Base texture         — UIImage from WkWebView snapshot
2. Highlight rects      — coloured rectangles blended over the text positions
3. Paper grain          — multiply blend of bundled grain tile (if enabled)
4. Warmth adjustment    — CIColorMatrix shifting white point (if non-zero)
5. Leading-edge shadow  — CILinearGradient composite at spine edge (if enabled)
```

**Highlight compositing — no WKWebView re-render:**

When a highlight exists on a page, its bounding rects (in screen coordinates, stored in the annotation model — see §3.6) are composited over the base texture using a Core Image blend:

```swift
func compositeHighlights(
    onto baseImage: CIImage,
    highlights: [HighlightRect]
) -> CIImage {
    var result = baseImage
    for highlight in highlights {
        // Semi-transparent colour rectangle blended over the text region.
        // CIConstantColorGenerator + CIBlendWithAlphaMask gives precise colour control.
        let colour = CIColor(cgColor: highlight.color.withAlphaComponent(0.3).cgColor)
        let colourImage = CIImage(color: colour).cropped(to: highlight.rect)
        result = colourImage.composited(over: result)
    }
    return result
}
```

Adding or removing a highlight does not touch the WkWebView. The base texture is unchanged. A new compositing pass produces the updated UIImage, which replaces the current UIImageView's image. On modern hardware this is effectively instantaneous.

**Paper grain compositing:**

```swift
// Grain tile is loaded once at startup and reused.
// CIMultiplyBlendMode over the page image at reduced opacity.
let grain = CIFilter(
    name: "CIMultiplyBlendMode",
    parameters: [
        kCIInputImageKey:           grainTile,  // grain tile, tiled to page size
        kCIInputBackgroundImageKey: pageImage
    ]
)
// Blend the grain at a fixed low opacity — amount is a constant, not user-tunable.
```

**Warmth adjustment:**

```swift
// CIColorMatrix shifts the white point toward amber (warm) or blue-white (cool).
// warmth is a Float in [-1.0, +1.0]; 0.0 = no adjustment.
let colorMatrix = CIFilter(name: "CIColorMatrix")
colorMatrix?.setValue(CIVector(x: 1.0 + warmth * 0.15,
                               y: 1.0,
                               z: 1.0 - warmth * 0.1, w: 0), // RGB multipliers
                      forKey: "inputRVector")
// ... similar for G and B vectors tuned for natural warmth/cool shift
```

**Compositing pipeline function:**

```swift
func compositePage(
    base: UIImage,
    highlights: [HighlightRect],
    settings: RenderingEffects    // grain on/off, warmth value, shadow on/off
) -> UIImage {
    var image = CIImage(image: base)!
    image = compositeHighlights(onto: image, highlights: highlights)
    if settings.paperGrainEnabled {
        image = compositeGrain(onto: image)
    }
    if settings.warmth != 0 {
        image = applyWarmth(settings.warmth, to: image)
    }
    if settings.spineShadeEnabled {
        image = compositeSpineShade(onto: image)
    }
    let context = CIContext()
    return UIImage(cgImage: context.createCGImage(image, from: image.extent)!)
}
```

The `CIContext` should be created once and reused — creating it per-composition is expensive.

### 3.5 Stage 3: Display Layer

**UIPageViewController with UIImageView page controllers:**

Each page in UIPageViewController is a `PageImageViewController` — a minimal `UIViewController` that contains a single `UIImageView` (content mode: `.scaleAspectFit`, or `.center` depending on page alignment preference). The UIImageView shows the composited UIImage from Stage 2.

```swift
class PageImageViewController: UIViewController {
    let imageView = UIImageView()
    var pageImage: UIImage? {
        didSet { imageView.image = pageImage }
    }
    // Accessibility: imageView.isAccessibilityElement = false
    // The WKWebView interaction layer (§3.6) is the accessibility provider.
}
```

UIPageViewController receives `PageImageViewController` instances. It never sees a WKWebView. Page curl and slide animations operate on `UIImageView`-backed view controllers — the snapshot UIPageViewController takes at gesture start captures a UIImage-backed view, which is trivially fast.

**The display layer never waits for rendering.** If a requested page image is not yet in cache (e.g., the user flips pages faster than pre-rendering), display a neutral placeholder (the theme background colour) until the image is ready. This should be rare on modern hardware.

### 3.6 Text Selection — Interaction Layer

The WKWebView interaction layer is an always-loaded WKWebView that sits **behind** the UIImageView display layer. It contains the same chapter content at the same CSS Columns position. It is the source of truth for text — it is what the user selects from and annotates.

**Normal reading state:**
- UIImageView: `isUserInteractionEnabled = true` (receives swipe gestures for page turns)
- Interaction WKWebView: `isUserInteractionEnabled = false` (present but passive)
- The interaction WKWebView is loaded with the same chapter URL, same CSS, translated to the same column as the current page

**Text selection activation:**
A `UILongPressGestureRecognizer` on the UIImageView detects long press. On recognition:

```swift
func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    if gesture.state == .began {
        // 1. Disable UIImageView interaction so the long press falls through
        pageImageView.isUserInteractionEnabled = false
        // 2. Enable WebView interaction — it now receives the continued gesture
        interactionWebView.isUserInteractionEnabled = true
        // 3. The long press continues into the WebView, activating native text selection
        // Note: gesture forwarding requires routing the UITouch to the WebView's
        // hit-test layer. Implementation detail: see gesture forwarding notes below.
    }
}
```

Because the UIImageView and WKWebView are pixel-aligned showing identical content (same CSS, same column position), the transition is imperceptible. The text selection handles appear on the visible content as expected.

**Returning to reading state:**
When the user dismisses text selection (tap outside selection, or completes a highlight/note action), interaction returns to UIImageView:

```swift
interactionWebView.isUserInteractionEnabled = false
pageImageView.isUserInteractionEnabled = true
```

**Getting selection geometry for highlights:**

After a text selection is made and the user taps "Highlight":

```javascript
// Called via evaluateJavaScript after selection is confirmed.
// Returns the bounding rects of the selection in page coordinates.
function getSelectionRects() {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return [];
    const range = selection.getRangeAt(0);
    const rects = Array.from(range.getClientRects());
    return rects.map(r => ({
        x: r.left, y: r.top, width: r.width, height: r.height
    }));
}
```

These rects are stored in the annotation model alongside the character offset range (for position persistence) and the highlight colour. On next page load, these rects are passed to Stage 2 compositing. The base texture does not need to be re-rendered — the highlight is purely a compositing layer.

**Keeping the interaction WebView in sync:**

The interaction WebView must always be positioned at the same column as the current display page. When the page changes, call `goToPage(newIndex)` on the interaction WebView. Since the interaction WebView is loaded with identical CSS and the same chapter URL via R2Streamer, the column positions are identical to those of the rendering WebView that produced the UIImages.

**Find in page:**

`WKWebView.find(_:configuration:completionHandler:)` (iOS 16+) runs on the interaction WebView. The user activates find-in-page, the interaction layer becomes visible (or the UIImageView is suppressed), find operates natively, the user is done, display layer returns. Match positions can also be composited as coloured highlights in Stage 2 if a more visually integrated experience is desired.

---

## 4. Reader View UI

### 4.1 Layout and Reader Chrome

The reader view is full-screen. There are two distinct chrome systems with different invocation models and different jobs.

---

**Chrome System 1 — Title and Page Metadata (tap to toggle)**

Tapping anywhere in the main reading area (not the left/right page-turn edges, not the bookmark ribbon) toggles the title strip and page metadata display.

- **Hidden state (reading mode):** only the bookmark ribbon (§4.7) is visible on the page.
- **Shown state:** a slim title strip appears at the top; a metadata strip at the bottom. Both fade in and out with a short opacity transition.

**Title strip (top, tap-toggled):** A single line showing the book title or chapter title (user's choice, configurable). Minimal — just text on the reading surface.

**Metadata strip (bottom, tap-toggled):** A single line of reading position information. Default: `Chapter N of M  ·  Page X of Y  ·  Y − X pages remaining in chapter`. Configurable in Advanced Settings (§4.5).

---

**Chrome System 2 — Options Panel (invocation TBD)**

A **floating panel** — not a full-screen sheet, not a nav bar. The book remains partially visible behind it. Dismissed by tapping outside or swiping away.

**What the panel contains:**
- Table of Contents
- Bookmarks, Highlights & Notes (annotation review)
- Reader Settings (Aa — typography panel)
- Share Book…
- Book Details

**Invocation mechanism: open question.** Candidates with trade-offs:

| Option | Feel | Trade-offs |
|---|---|---|
| Swipe from left edge | Natural on iPad | Conflicts with system back gesture on iPhone |
| Persistent small icon | Always discoverable | Adds permanent element to reading surface |
| Long press on title strip | Logical | Requires chrome visible first |
| Two-finger tap | Clean | Discoverability problem |
| Swipe up from bottom edge | Natural iPhone | Conflicts with home gesture |

**Recommendation:** persistent small icon (same visual weight as bookmark ribbon) in a fixed corner. Always one tap away, no gesture conflicts.

---

**Persistent on-page elements (always visible):**
- Bookmark ribbon (§4.7) — top-right corner (or leading edge in skeuomorphic mode)
- Options panel icon (design TBD)

**Tap zones:**
- Left edge (~35%) → previous page
- Right edge (~35%) → next page
- Centre (~30%) → toggle title/metadata strips (System 1)
- Persistent icons → their specific actions

**Status bar:** visible and dimmed by default. Full immersive mode toggled from the options panel.

**Gestures:**
- Swipe left / right → page turns
- Long press on text → text selection (§3.6)
- System swipe from left edge → back to library

### 4.2 Reader Settings Panel

Accessible via the **Reader Settings** item in the options panel. Opens as a bottom sheet.

**Surface controls:**
- Font size slider (with live preview)
- Font family picker
- Line spacing slider
- Paragraph spacing slider
- Theme selector (Light / Dark / Sepia) with colour swatches
- Page turn style selector
- Margin sliders (left/right linked by default; unlinkable for independent control)

**"More Typography…" row** (tap to expand):
- Letter spacing slider (-2px to +4px)
- Text alignment toggle (Left / Justified)
- Background warmth slider (−100 cool to +100 warm, default 0)
- "Use book fonts" toggle
- Paper grain toggle (Light and Sepia themes only)

**Live preview:** settings changes update the display immediately. For typography changes (font, size, margins): the interaction layer WebView is re-rendered and a new snapshot composited. The UIImageView updates without a page reload. For visual effects (warmth, grain): Stage 2 compositing re-runs on the current base texture — fast, no WebView involvement.

**Per-book overrides toggle** — at the top of the panel:

> **Applies to:** [My Defaults] [This Book]

- **My Defaults:** change updates global `ReaderSettings`. All books without per-book overrides change immediately.
- **This Book:** change creates or updates `BookReaderOverrides` for the current book. Globals untouched.

When a book has active per-book overrides, the panel shows "Custom settings active for this book." A **Clear book settings** button reverts to global defaults.

### 4.3 Table of Contents

- Accessible via the **Table of Contents** item in the options panel.
- Displays the epub's navigation document as a hierarchical list.
- Tapping a TOC entry navigates to that chapter/section.
- Current position is highlighted in the TOC.

### 4.4 Progress Display

**Passive progress — page stack edges (§2.9):** book-level progress communicated visually through the fanned page edges.

**Active metadata — tap-toggled strip (System 1 from §4.1):** precise chapter-level information.

- **Mode A — chrome shown:** default: `Chapter N of M  ·  Page X of Y  ·  Y − X pages remaining in chapter`
- **Mode B — clean reading mode:** no persistent indicator.

**Optional metadata elements** (each independently togglable in Advanced Settings):

| Element | Example | Useful for |
|---|---|---|
| Chapter position | Page 7 of 24 | Where you are in the chapter |
| Pages remaining in chapter | 17 pages left | Planning your session |
| Chapter indicator | Chapter 3 of 12 | Context in the book |
| Book progress % | 31% | Precise overall progress |
| Reading time remaining | ~3h 20m left | Session planning |
| Time remaining in chapter | ~18m | Immediate planning |
| Clock | 9:41 PM | When status bar is hidden |

**Progress scrubber:** a full-width draggable slider in the options panel. Drag to jump anywhere in the book instantly. A floating label shows the chapter name at the scrub position. This is a first-class navigation tool.

**Auto-bookmark on scrub:** Codex silently saves current position before any scrubber jump. A "Return to previous position" prompt appears after the jump. Toggleable in Advanced Settings (default: on).

**Reading speed and time estimation:** tracks words read per session. Default: 250 wpm. Self-corrects over sessions. Shown as approximate. Can be turned off.

**"Go to page" is not a v1 feature.** Epub page numbers are not stable across font sizes and screen geometries.

### 4.6 First-Open Typography Prompt

The first time a newly ingested book is opened, Codex shows a **typography choice overlay** before the book begins. Appears **only once per book** on first open.

#### The Three Choices

| Choice | Label | What it does |
|---|---|---|
| **A** | Publisher's Style | Epub's own CSS respected, no user overrides. Sets `typographyMode = .publisherDefault`. |
| **B** | My Defaults | User's global `ReaderSettings` applied. Sets `typographyMode = .userDefaults`. |
| **C** | Customize | Opens in-reader typography panel in "This Book" mode. Sets `typographyMode = .custom`. |

The choice is stored permanently. Revisited via **Book Detail → Reset typography for this book**.

#### Finding the Preview Excerpt

The overlay shows real text from the book. Lookup order:

1. **Epub 3 `landmarks`** — look for `bodymatter` or `text` start point.
2. **Epub 2 `guide`** — look for a `text` reference.
3. **Heuristic fallback** — scan linear spine items; skip filenames matching `cover`, `titlepage`, `copyright`, `toc`, `colophon`, `dedication`; take first item with > 200 words.
4. **Last resort** — first linear spine item.

Excerpt: approximately 250–350 words. Both choices rendered in the off-screen WKWebView and snapshotted for display — no live WebView in the overlay UI.

#### The Comparison UI

**On iPhone:** a modal sheet. A segmented control toggles live preview between Publisher's Style and My Style. Three buttons at the bottom.

**On iPad:** side-by-side split. Left: Publisher's Style. Right: My Defaults. Linked scroll. Three buttons at the bottom.

Both layouts include a small **"Skip for now"** option that defaults to "My Defaults" without permanently storing a choice.

#### The Customize Path — Panel Detail

When the user taps **Customize…**, the overlay transitions into the in-reader typography panel in "This Book" mode.

**Starting point:** initialised from the epub's computed styles (`window.getComputedStyle(document.body)` via JavaScript on the interaction WebView). The user adjusts from the publisher's choices.

**Starting point selector:**

> **Start from:** [Publisher's Style ▾]

Options: Publisher's Style / My Defaults / [Series Name, Book N] (if applicable).

**Quick-apply switches:** individual toggles for Font Size, Font Family, Margins, Line Spacing, Letter Spacing — each showing the current global default value inline.

**Done** saves overrides as `BookReaderOverrides`, sets `typographyMode = .custom`, opens the book.

#### Publisher Mode — What Gets Overridden

When `typographyMode = .publisherDefault`, user CSS overrides are not injected. Two exceptions always apply:
- **Theme** (background and text colour) — always injected.
- **Minimum font size floor** (~10pt) — safety net for broken epub CSS.

### 4.7 Navigation Controls — Bookmark, TOC, and the More Menu

#### One-Tap Bookmark

A bookmark ribbon is permanently visible in the corner of the reading page.

**Visual:** a ribbon shape with a V-cut at the bottom.
- **Outline only** (default): no bookmark on this page.
- **Solid red** (bookmarked): bookmark exists. Transition is immediate on tap with subtle haptic.

**Position:**
- Standard mode: top-right corner of the reading area.
- Skeuomorphic mode: leading edge, near the spine.

**Adding a label:** long-press opens a small inline text field below the ribbon. Unlabelled bookmarks display the chapter name and position.

**Current page definition:** chapter href + character offset of the first visible character (paginated modes), or scroll percentage (scroll mode).

#### Options Panel Contents

| Item | Action |
|---|---|
| **Progress slider** | Full-width scrubber. Drag to jump anywhere. Chapter name shown as scrub label. |
| **Current chapter info** | Chapter title, number, page count. |
| **Table of Contents** | Hierarchical navigation. Current position highlighted. |
| **Bookmarks, Highlights & Notes** | Annotation review. Filtered tabs: All / Highlights / Notes / Bookmarks. |
| **Reader Settings** | Typography panel (§4.2) |
| **Share Book…** | iOS system share sheet with the epub file |
| **Book Details** | Book Detail view from Library Manager |
| **Full Screen** | Toggles immersive mode (hides status bar) |

### 4.8 Text Selection — Look Up, Search Web, and Annotations

When the user long-presses on the reading surface, the interaction layer (§3.6) activates. The WKWebView receives the gesture and the standard iOS text selection UI appears. Because the interaction WebView contains real text at the same visual position as the UIImage display layer, the experience is seamless — the user sees no transition.

**Codex extends — but does not replace — the standard iOS callout.**

**Callout bar action order:**

`Highlight · Note · Copy · Look Up · Search Web · Translate · Share · ···`

| Action | What it does | Implementation |
|---|---|---|
| **Highlight** | Creates a highlight annotation using the last-used colour | Custom `UIAction` via `UIEditMenuInteraction` (iOS 16+). Selection rects captured via JS and stored. Stage 2 compositing updated. |
| **Note** | Opens note editor; creates a highlight+note annotation | Custom `UIAction` |
| **Copy** | Copies selected text to pasteboard | Standard iOS — preserved |
| **Look Up** | iOS native dictionary/reference/Wikipedia lookup | Standard iOS — preserved. **This is what Apple Books recently removed. Codex does not remove it.** |
| **Search Web** | Opens Safari with selected text | Standard iOS — preserved. Test on each target iOS version. |
| **Translate** | iOS system translation panel (iOS 14+) | Standard iOS — preserved |
| **Share** | iOS share sheet with selected text and attribution | Standard iOS Share + attribution |
| **···** | Overflow for additional system items | Standard iOS |

`UIEditMenuInteraction` is the modern API (iOS 16+) for customising the callout in a `UIView`/`WKWebView`. Custom actions are added via `willPresentMenuWithAnimator:`. Do not suppress or replace any system-provided items.

### 4.9 Text Sharing — Share Sheet, Attribution, and No Artificial Limits

When the user selects text and taps **Share**, the iOS share sheet opens with the selected text as payload.

**Attribution:** by default, Codex appends:

> *[Selected text]*
>
> — [Book Title], [Author]

Attribution can be turned off in Advanced Settings (default: on).

**No artificial limits.** Codex does not impose character limits on text sharing. The user owns these books (DRM-free only).

**Additional share actions:**
- **Copy with Citation** — text + attribution + chapter/position reference
- **Add to Note** — Notes.app extension if installed

### 4.5 Advanced Settings (App Settings → Reading → Advanced)

| Setting | Description | Default |
|---|---|---|
| **Font size minimum** | Lower bound of font size slider | 8pt |
| **Font size maximum** | Upper bound of font size slider | 72pt |
| **Publisher mode safety floor** | Minimum font size in publisher mode | 10pt |
| **Match Surroundings threshold** | Brightness % below which Dark activates | 30% |
| **Background warmth default** | Default warmth slider position (−100 to +100) | 0 |
| **iPad orientation auto-switch** | Auto-switch to Scroll on landscape→portrait rotation | On |
| **iPad rotation lock** | Lock iPad to landscape | Off |
| **iPhone rotation lock** | Lock iPhone to portrait | On |
| **Tap zone layout** | Left / Centre / Right tap area sizes | 35% / 30% / 35% |
| **Status bar in reader** | Show / Hide (full immersive) | Show |
| **Show time in reader chrome** | Small clock when status bar hidden | Off |
| **Show battery in reader chrome** | Battery indicator when status bar hidden | Off |
| **Metadata strip: chapter position** | Show "Page N of Y" | On |
| **Metadata strip: pages remaining** | Show "Y − X pages remaining" | On |
| **Metadata strip: chapter indicator** | Show "Chapter N of M" | Off |
| **Metadata strip: book progress %** | Show overall percentage | Off |
| **Metadata strip: time remaining** | Show reading time estimate | On |
| **Metadata strip: time scope** | Whole book / Current chapter | Chapter |
| **Metadata strip: clock** | Show clock | Off |
| **Title strip: title source** | Book title or Chapter title | Chapter title |
| **Auto-bookmark on scrub** | Save position before scrubber jump | On |
| **Reading speed baseline** | Manual wpm override | Auto |
| **Fixed-layout epub handling** | Zoom-and-pan or auto-fit | Zoom-and-pan |
| **Pre-render page lookahead** | Number of pages ahead to pre-render | 3 |
| **Page image cache size** | Max cached page UIImages in memory | 10 |
| **Reset all reader settings** | Restore typography and layout to defaults | — |

---

## 5. Performance Requirements

- **Chapter first-render time:** < 400ms from chapter open to first page image ready. Subsequent pages pre-rendered in the background.
- **Page turn animation:** always smooth at 60fps / 120fps ProMotion. UIImageView page controllers ensure the animation layer never waits on rendering.
- **Typography settings change:** updated page images begin replacing the displayed page within 200ms of a settings change, working outward from the current page.
- **Highlight compositing:** adding or removing a highlight produces an updated page UIImage within 50ms on current hardware. The compositing pass does not involve WKWebView.
- **Visual effects (warmth, grain):** Core Image filter chain completes in < 16ms per page on iPhone 15 Pro or newer (one frame at 60fps). Effects changes are instantaneous from the user's perspective.
- **Memory:** page image cache is bounded (configurable, default 10 pages). Images beyond the cache window are evicted and re-composited on demand. Two WKWebView instances are maintained per open book: the off-screen renderer and the interaction layer. Total WKWebView count is bounded to 2 regardless of page count.
- **Pre-render queue:** runs on a low-priority background queue (`DispatchQueue.global(qos: .utility)`). Yields immediately to user interaction. Pre-renders current chapter first, then adjacent chapters.

---

## 6. Accessibility

VoiceOver and other accessibility tools are not a design goal for Codex v1. The WKWebView interaction layer (§3.6) is always loaded with valid HTML content and is present in the view hierarchy, so accessibility tools that traverse the view tree will encounter real, semantically valid content rather than an image. This is a passive fallback, not an engineered accessibility implementation.

The UIImageView display layer must have `isAccessibilityElement = false` so accessibility tools traverse to the WKWebView below rather than stopping at an opaque image.

Minimum tap target size: 44×44pt for all interactive elements (bookmark ribbon, options icon, etc.).

---

## 7. Settings Data Model

### 7.1 Global Reader Settings

Stored in UserDefaults and synced via the Sync Engine. These are the user's personal defaults — applied to every book unless a per-book override exists.

```swift
struct ReaderSettings: Codable {
    var fontSize: CGFloat          // e.g., 18.0 (points)
    var fontFamily: String         // e.g., "Georgia"
    var useBookFonts: Bool         // false = always override with fontFamily
    var lineSpacing: CGFloat       // e.g., 1.4
    var paragraphSpacing: CGFloat  // e.g., 0.8 (em units) — default 0.8em
    var letterSpacing: CGFloat     // e.g., 0.0
    var textAlignment: TextAlign   // .left | .justified
    var theme: ReaderTheme         // .light | .dark | .sepia
    var pageTurnStyle: PageTurn    // .curl | .slide | .scroll
    var marginTop: CGFloat
    var marginBottom: CGFloat
    var marginLeft: CGFloat
    var marginRight: CGFloat
    var warmth: Float              // -1.0 (cool) to +1.0 (warm); 0.0 = neutral
    var paperGrainEnabled: Bool    // paper texture overlay; Light and Sepia only
    var spineShadeEnabled: Bool    // leading-edge gradient shadow
}
```

### 7.2 Per-Book Typography Mode

```swift
enum BookTypographyMode: String, Codable {
    case publisherDefault  // Epub's own CSS respected; no user overrides (except theme + floor)
    case userDefaults      // User's global ReaderSettings applied in full
    case custom            // BookReaderOverrides merged with ReaderSettings (see §7.3)
}
```

Default for newly ingested books before the first-open prompt: `.userDefaults`.

### 7.3 Per-Book Overrides

```swift
struct BookReaderOverrides: Codable {
    var fontSize: CGFloat?
    var fontFamily: String?
    var useBookFonts: Bool?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?
    var letterSpacing: CGFloat?
    var textAlignment: TextAlign?
    var theme: ReaderTheme?
    var pageTurnStyle: PageTurn?
    var marginTop: CGFloat?
    var marginBottom: CGFloat?
    var marginLeft: CGFloat?
    var marginRight: CGFloat?
    var warmth: Float?
    var paperGrainEnabled: Bool?
    var spineShadeEnabled: Bool?
}
```

### 7.4 Effective Settings — Merge at Render Time

```swift
// Returns the effective ReaderSettings for CSS injection.
// Returns nil for publisherDefault (inject only theme colours + floor).
func effectiveSettings(global: ReaderSettings, book: Book) -> ReaderSettings? {
    switch book.typographyMode {
    case .publisherDefault:
        return nil
    case .userDefaults:
        return global
    case .custom:
        guard let overrides = book.typographyOverrides else { return global }
        return ReaderSettings(
            fontSize:          overrides.fontSize          ?? global.fontSize,
            fontFamily:        overrides.fontFamily        ?? global.fontFamily,
            useBookFonts:      overrides.useBookFonts      ?? global.useBookFonts,
            lineSpacing:       overrides.lineSpacing       ?? global.lineSpacing,
            paragraphSpacing:  overrides.paragraphSpacing  ?? global.paragraphSpacing,
            letterSpacing:     overrides.letterSpacing     ?? global.letterSpacing,
            textAlignment:     overrides.textAlignment     ?? global.textAlignment,
            theme:             overrides.theme             ?? global.theme,
            pageTurnStyle:     overrides.pageTurnStyle     ?? global.pageTurnStyle,
            marginTop:         overrides.marginTop         ?? global.marginTop,
            marginBottom:      overrides.marginBottom      ?? global.marginBottom,
            marginLeft:        overrides.marginLeft        ?? global.marginLeft,
            marginRight:       overrides.marginRight       ?? global.marginRight,
            warmth:            overrides.warmth            ?? global.warmth,
            paperGrainEnabled: overrides.paperGrainEnabled ?? global.paperGrainEnabled,
            spineShadeEnabled: overrides.spineShadeEnabled ?? global.spineShadeEnabled
        )
    }
}
```

### 7.5 Highlight Rects — Annotation Compositing Data

Highlight rects are stored in the `Annotation` model (Annotation System Module 6) alongside character offsets. The Rendering Engine reads them at compositing time.

```swift
// Stored per annotation, in addition to character offsets.
// Units: CGRect in page coordinate space (same coordinate system as WKWebView
// at the time of selection, i.e. column-zero-translated coordinates).
struct HighlightRect: Codable {
    let rect: CGRect    // bounding rect of one text line in the selection
    let color: String   // hex colour string, e.g. "#FFD60A" for yellow
}
// An annotation may have multiple HighlightRects (one per line of selected text).
```

Rects are captured from `range.getClientRects()` at selection time (see §3.6). They are stored with the annotation and used directly in Stage 2 compositing without any re-measurement.

---

## 8. Open Questions

- **Epub 3 Media Overlays (read-aloud):** Out of scope for v1. Architecture does not preclude it.

- **Fixed-layout epubs:** Detect these via R2Streamer's `Publication.metadata.presentation.layout`. Display fixed-layout epubs as-is with zoom/pan. User typography overrides do not apply. Show a clear notice: "This book uses a fixed layout and cannot be restyled." CSS Columns and the pre-render pipeline do not apply to fixed-layout epubs — they are loaded directly into a scrollable WKWebView. The Advanced Setting for fixed-layout handling (§4.5) specifies zoom-and-pan vs auto-fit.

- **Right-to-left language support:** WebKit handles RTL text natively. RTL also affects tap-to-turn direction and CSS Columns translation direction. Auto-detect from R2Streamer's `Publication.metadata.languages`. Needs explicit testing.

- **In-reader text search (find in book):** `WKWebView.find(_:configuration:completionHandler:)` (iOS 16+) on the interaction WebView. Low implementation cost. Recommendation: include in v1. Options panel needs a Search item; results UI needs a bottom bar with match count and prev/next navigation.

- **Options panel invocation mechanism:** Candidates listed in §4.1. Persistent small icon recommended. Decide during visual development.

- **Scroll mode pre-rendering:** In scroll mode, pages have no discrete boundaries. Decide during implementation whether to: (a) pre-render the whole chapter as one tall image and display in a UIScrollView, (b) display the WKWebView directly in scroll mode (simplest), or (c) use a hybrid tiling approach. Option (b) is recommended for v1 — the pre-render/UIImage architecture applies only to Curl and Slide modes.

- **Highlight rect coordinate stability across re-renders:** If typography settings change and pages are re-rendered, existing highlight rects (captured at a specific font size and column width) may no longer correspond to the correct text positions. Resolution options: (a) re-capture rects from the interaction WebView after each re-render using stored character offsets, (b) store only character offsets and derive rects lazily at display time. Option (b) is architecturally cleaner — store offsets as the source of truth, derive rects at Stage 2. Implement if (a) proves unreliable.

- **Custom Metal page curl (post-v1):** The UIPageViewController curl is good and serves v1 well. The UIImage-based architecture makes a migration to a custom Metal curl straightforward — the content textures are already available. Revisit when the reading experience is otherwise complete.

- **Readium version and API stability:** Pinned at **3.8.0** (March 2026). Validated against the actual Readium 3.8 API during the Readium-experiment branch. The async `AssetRetriever.retrieve` / `PublicationOpener.open` signatures have been stable across 3.x. The HTTP server API (`GCDHTTPServer`) is deprecated for removal in a future Readium release — see §3.2 and `CLAUDE.md` "Readium GCDHTTPServer is deprecated" handoff note for the migration plan to a custom `WKURLSchemeHandler`.

- **Ingestion-time epub parsing:** the legacy custom `EpubParser` is still used by `IngestionPipeline` for metadata + cover extraction at ingest time. This is a deliberate scoping choice for the Readium-experiment branch (see `CLAUDE.md` "Ingestion still on the custom epub parser" handoff note). Migrate ingestion to Readium when the custom parser fails on a real epub or when the dual-parser code burden outweighs the migration cost. After migration the entire `Codex Reader/EpubParser/` source group is deleted.

---

*Module status: Architecture substantially revised — pre-render-to-UIImage pipeline, CSS Columns pagination, Core Image compositing for highlights and visual effects, WKWebView interaction layer for text selection, R2Streamer as targeted epub parsing dependency. R2Navigator explicitly not used. All prior UI specifications (chrome, settings panel, typography prompt, bookmark, annotation, skeuomorphic surface) preserved.*  
*Last updated: April 2026*
