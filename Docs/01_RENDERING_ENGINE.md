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

The user selects a page turn style in Settings. All three available styles are either native Apple APIs or default WebView behavior — none require custom animation code.

| Style | Description | Implementation | Cost |
|---|---|---|---|
| **Page Curl** | Skeuomorphic paper curl. The page peels back revealing the next page beneath, with a realistic curl shadow. The curl physically follows the user's finger. | `UIPageViewController` with `transitionStyle: .pageCurl`, wrapped in `UIViewControllerRepresentable` for SwiftUI | Public Apple API (since iOS 5), not deprecated, confirmed available on iOS 17+. No third-party library needed or permitted. |
| **Slide / Swipe** | Page follows the user's finger horizontally; release past the midpoint completes the turn, release before snaps it back. A tap on the left/right edge also turns the page. "Slide" and "Swipe" are the same built-in gesture — there is no distinction. | `UIPageViewController` with `transitionStyle: .scroll` | Native Apple API — free |
| **Scroll** | Continuous vertical scroll. No page breaks, no pagination. The chapter is one scrollable surface. Progress is a continuous percentage. | `WKWebView` without pagination imposed — the WebView's natural scroll behavior. | Default behavior — free |

Fade was considered and dropped. It requires hand-rolled animation code and adds no reading value.

**Implementation note on Page Curl:** `UIPageViewController` with `.pageCurl` is a public UIKit API, confirmed non-deprecated and available on iOS 17+. It is not a private API. SwiftUI integration is via `UIViewControllerRepresentable` — this is the correct and only approach. There are community reports of occasional animation lag since iOS 16 in some configurations; test on device and tune if needed, but the API itself is fully supported. Do not substitute a third-party library.

**Page Curl gesture behaviour — specific requirements:**

- **Drag only.** Page turns are initiated exclusively by a drag/swipe gesture. Taps anywhere on the page do NOT turn pages in Curl mode. The tap gesture recogniser on `UIPageViewController` must be disabled — remove or disable it explicitly, keeping only the pan/swipe gesture recogniser. Taps are reserved for toggling the reader chrome (System 1, §4.1). **Implementation order:** confirm the page curl view is working correctly before disabling the tap gesture recogniser. When picking up this project, add disabling the tap recogniser to the handoff task list if it has not yet been done.

- **The back of the curling page shows the next page.** As the page peels back, the underside of the curl shows a dimmed, mirrored preview of the next page — not a blank or grey surface. This is the default `UIPageViewController` behaviour and must be preserved. It is achieved by ensuring the next page's view controller is loaded and snapshotted before the gesture begins, which is why adjacent chapter pre-loading (keeping current + 1 ahead + 1 behind in memory) is a hard requirement, not a nice-to-have.

- **How the curl works technically.** At the moment a drag begins, `UIPageViewController` snapshots the current and adjacent page views as bitmaps. The curl animation operates on those snapshots — it is not live-rendering the WKWebView during the gesture. This is why pre-loading adjacent chapters before the gesture starts is critical: a WKWebView that hasn't finished rendering will produce a blank or stale snapshot. The pre-load must be complete before the user's finger touches the page.

**Anti-requirement:** Apple Books switches from Page Curl to Slide when font size exceeds a certain threshold relative to the epub's declared size. Codex must never do this. The selected style is locked until the user changes it in Settings. The only exception is the orientation-triggered auto-switch described below.

**Scroll mode note:** Scroll mode changes the fundamental reading metaphor — there are no "pages." The bottom bar shows a percentage bar rather than "Page N of M." Chapter transitions happen automatically when the user scrolls past the end of the current chapter (each chapter loads fully in sequence — not the entire book at once).

### 2.6 Orientation and Auto-Switch to Scroll

Rotating an iPad to portrait orientation while reading is a deliberate gesture — most commonly used to switch the reading surface to continuous scroll for text selection across what would otherwise be a page boundary. In Apple Books, selecting text that starts on a right-hand page and ends on a left-hand page requires approximately seven taps. In Codex, the user rotates the device and selects in one gesture.

**Auto-switch behaviour:**

| Situation | Behaviour |
|---|---|
| iPad, reading in landscape (Curl or Slide), user rotates to portrait | Auto-switch to Scroll mode. Saves the previous style. |
| iPad, device already in portrait when book opens | Do not auto-switch. The user is already in their preferred orientation; respect their chosen page turn style. |
| iPad, user rotates back to landscape | Restore the previously saved page turn style. The setting is unchanged — this was a temporary mode for a task. |
| iPhone, any rotation | No auto-switch. iPhone users typically read in portrait; rotation is uncommon and should not change the reading mode. |

The auto-switch is triggered by the act of rotation, not by the resulting orientation. A device that was portrait when the book opened is not "the user rotated to portrait" — it is the user's baseline.

**Sensible defaults** (pending user research validation):
- iPad: rotation enabled, auto-switch on
- iPhone: rotation locked to portrait, no auto-switch

Both are configurable in Settings → Reading → Orientation (see Advanced Settings §4.5).

**Per-book override:** the orientation settings can be overridden per-book via `BookReaderOverrides`, for the rare case where a specific book works better in a non-default orientation mode.

### 2.7 Pagination

- All non-scroll modes use paginated display.
- Pagination is calculated based on the rendered content area (accounting for margins, font size, and line spacing) after the epub chapter is loaded into the WKWebView.
- Page count and current page number are derived programmatically from scroll position and content height.
- Chapters are loaded as discrete units; the user pages through a chapter and then moves to the next.

### 2.8 Additional Typography Controls

| Setting | Range / Options | Default |
|---|---|---|
| Line spacing | 1.0× to 2.5× (in 0.1× steps) | 1.4× |
| Paragraph spacing | 0em to 2.0em (in 0.1em steps) | 0.8em |
| Letter spacing | -2px to +4px | 0px |
| Text alignment | Left, Justified | Left |
| Theme | Light, Dark, Sepia (see §2.9) | Follows system (see §2.9) |

**Paragraph spacing note:** Epub CSS varies widely — many publishers do not specify paragraph spacing, and some explicitly set it to zero, using first-line indent as the paragraph separator instead (traditional book typography). Codex always injects a paragraph spacing value regardless of what the epub specifies, so the user's preference wins. The default of 0.8em provides comfortable visual separation without looking like a web page. Users who prefer the indent-only convention can set this to 0em. The injected CSS targets `p` elements with `margin-bottom` — see §3.3 for the full CSS injection spec.

### 2.9 Skeuomorphic Reader Surface

The reading surface has several independent skeuomorphic options. All are off by default — the modern flat reading UI is the baseline. Each element can be enabled individually in Settings → Reading → Reader Appearance.

#### Paper Surface

A subtle, low-contrast paper grain texture applied as an overlay on the reading background. Warm and tactile — adds the feeling of a physical page without calling attention to itself.

- Available in Light and Sepia themes only; forced off in Dark theme (dark paper texture looks artificial and hurts legibility).
- When Paper is active and the page turn style is Page Curl or Slide, a faint drop shadow beneath the page gives the impression the page is resting slightly above a surface. Single-pass shadow, no 3D rendering.
- The texture is a high-quality, licence-free static image tile bundled with the app. Not dynamically generated.

#### Page Stack Edges

The trailing edge of the reading area shows a thin strip of fanned, layered page edges — replicating what the pre-iOS 7 iBooks app showed and what every real book shows when you hold it. It communicates at a glance how deep into the book you are, the way a physical book does in your hand.

- Rendered as a custom decorative view layered on the trailing edge of the reader container, outside and behind the WKWebView content area. Does not affect rendering or layout of the reading surface itself.
- The apparent thickness of the stack scales with remaining reading progress — a full layered stack early in the book, a thin sliver near the end. Note: Apple's original iBooks implementation did not do this — the stack was a fixed-thickness decoration regardless of position. Codex's version is an improvement: the stack is a live, meaningful indicator, not just chrome.
- Page edges are always rendered in a slightly off-white/cream colour with subtle variation, regardless of theme — they represent the physical paper of the book, not the screen colour.
- Available in Page Curl and Slide turn styles only. Not shown in Scroll mode (no page metaphor in scroll).

#### Spine and Gutter

A visual representation of the book's binding.

**v1 — leading-edge binding shadow:** a narrow vertical gradient along the leading edge of the reading area, simulating the gentle curve of pages away from the spine. Subtle depth cue. Works on all devices and layout modes.

**Post-v1 — centre spine (two-column iPad landscape):** when two-column layout is implemented, a full centre spine with a deep gutter shadow appears between the facing pages — the open-book feel that was the centrepiece of the original iBooks iPad experience. This requires the two-column layout feature and is explicitly deferred. The setting is reserved in the data model from v1 so it can be activated without a data migration when two-column ships.

### 2.10 Theme and Dark Mode Detection

The user's reading theme (Light / Dark / Sepia) is set in the reader settings panel (§4.2). Codex offers five modes for determining the active theme, configurable in Settings → Reading → Theme:

| Mode | Behaviour |
|---|---|
| **Follow System** (default) | Light when iOS is Light; Dark when iOS is Dark. Sepia is never selected automatically — chosen manually or via schedule. |
| **Always Light** | Stays in Light regardless of system appearance. |
| **Always Dark** | Stays in Dark regardless of system appearance. |
| **Always Sepia** | Stays in Sepia regardless of system appearance. |
| **Scheduled** | User sets time-of-day transitions (e.g., Sepia 6 AM–8 PM; Dark 8 PM–6 AM). Transitions happen quietly. |
| **Match Surroundings** | Switches to Dark automatically when ambient light drops below a threshold. See below. |

**Per-book theme override:** theme is part of `BookReaderOverrides` (§7.3) — a specific book can be pinned to a different theme regardless of global setting.

**Follow-system implementation:** detected via `UITraitCollection.userInterfaceStyle`. The Rendering Engine observes trait collection changes and re-injects theme CSS if the system appearance changes while reading.

#### Match Surroundings — Ambient Light Detection

Apple Books offers a "Match Surroundings" mode that switches to Dark theme when the ambient light level gets low, independently of system appearance settings. This is the right behaviour — a reader in a dark room should get a dark screen even if their device system theme is set to Light.

**The limitation:** iOS does not expose the ambient light sensor to third-party apps through any public API. Apple Books almost certainly uses a private API unavailable to us. Two legitimate workarounds exist and need evaluation during the technical spike:

- **UIScreen brightness proxy:** when the device has auto-brightness enabled, iOS dims the screen as ambient light drops. Monitoring `UIScreen.main.brightness` for unprompted drops is an indirect but workable proxy for "the room got dark." No special permissions required. Imperfect — it won't fire if the user has auto-brightness disabled or has manually set a dim screen.
- **Front camera sampling:** a brief, silent camera capture to measure light level. More accurate. Requires a camera permission prompt — an awkward ask for a reading app. Likely not the right path.

**Recommendation:** implement the brightness-proxy approach for v1, clearly labelled "Matches surroundings (requires auto-brightness)" in Settings. Revisit with a better API if Apple opens the light sensor in a future iOS release. If the brightness proxy proves too unreliable in testing, the feature ships as the scheduled mode fallback.

The threshold (screen brightness level at which Dark kicks in) is configurable in Advanced Settings — default 30%.

#### Background Warmth — True Tone Independence

True Tone is Apple's system feature that shifts the display's colour temperature toward warm amber in warm ambient light, making white feel more like physical paper. It is controlled at the display driver level — third-party apps cannot override or control True Tone independently of the system setting.

**The problem:** photographers and colour-critical users often disable True Tone system-wide because it distorts their work. But in a reading context they might want the warm paper feel it provides — or they might want to keep their reading background clean and neutral regardless of ambient colour temperature.

**The solution:** a **Background Warmth** slider in the reader settings panel, separate from theme. It applies a subtle warm-to-cool colour tint to the reading background independently of the system's True Tone setting:

- At the centre position (default): the background is the theme's native colour — pure white in Light, `#F5EDD6` in Sepia, `#1C1C1E` in Dark.
- Sliding warmer: shifts the background toward amber/cream. For a Light theme user who wants a warmer-than-neutral reading surface without full Sepia.
- Sliding cooler: shifts toward blue-white. For a user with True Tone enabled system-wide who wants the reading surface to feel neutral despite True Tone's warmth.

This gives every user manual control over reading surface colour temperature regardless of their system True Tone setting — both the photographer who wants neutral white and the night reader who wants warm amber without going full Sepia. The slider is in the "More Typography…" section of the reader settings panel (§4.2), and in Advanced Settings for the default position.

---

## 3. Epub Rendering Architecture

### 3.1 Technology Choice: WKWebView

Epub files are, at their core, XHTML/HTML documents styled with CSS, structured by an OPF manifest. The most reliable way to render them on iOS is via **WKWebView**, which gives access to a full WebKit rendering engine.

The rendering flow:

```
epub file (on disk)
    ↓
Epub Parser (see §3.2)
    ↓
Chapter XHTML + assets extracted to a temporary directory
    ↓
WKWebView loads the chapter via loadFileURL(_:allowingReadAccessTo:)
    ↓
CSS injection applied (user preferences override epub styles)
    ↓
Rendered page displayed to user
```

WKWebView is wrapped in a SwiftUI `UIViewRepresentable` (a `WKWebViewWrapper`) to integrate with the SwiftUI view hierarchy.

### 3.2 Epub Parser

✅ **Decided: custom parser. No third-party library.**

ReadiumSDK and FolioReaderKit were evaluated and set aside. ReadiumSDK is a substantial library with its own streaming, pagination, and position management — features Codex doesn't need because WKWebView and the CSS injection system handle rendering entirely. Taking on that dependency footprint to use only the parser portion conflicts directly with §6.6 (minimize external dependencies) and §6.1 (simplest solution that works). A custom parser covering exactly what Codex needs is approximately 300–400 lines using only Apple frameworks already present in Foundation. The epub core structure — ZIP container, `container.xml`, OPF manifest, spine — has been stable since epub 2 and is not a moving target.

**What the parser does — and nothing more:**

The parser is a shared utility consumed by two modules: the Rendering Engine (loads chapter XHTML into WKWebView) and the Ingestion Engine (extracts metadata and cover art when a book is added to the library). It lives in its own group — `EpubParser/` — at the top level of the source tree, not nested inside either module.

**Step 1 — Unzip**

Epub files are ZIP archives. Unzip using a `Process()` call to the system `unzip` binary, which is always present. Extract to a temporary directory scoped to the book's UUID. No third-party zip library needed.

```swift
// Unzip the epub to a temp directory.
// Using Process()/unzip rather than a zip library — unzip is always present
// on the system and this avoids adding a dependency just for archive extraction.
func unzip(_ epubURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-o", epubURL.path, "-d", destinationURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw EpubParserError.unzipFailed
    }
}
```

**Step 2 — Find the OPF**

Read `META-INF/container.xml` using `XMLParser` (Foundation). Extract the `full-path` attribute of the `rootfile` element — this is the path to the OPF package document.

**Step 3 — Parse the OPF**

Parse the OPF file using `XMLParser`. Extract:

| Field | OPF location | Notes |
|---|---|---|
| Title | `<dc:title>` | Required |
| Author | `<dc:creator>` | May be multiple; join with ", " |
| Language | `<dc:language>` | Used for RTL detection |
| Cover image | `<meta name="cover">` or `properties="cover-image"` in manifest | Epub 2 and 3 differ here — handle both |
| Spine order | `<spine>` → `<itemref idref="...">` | Ordered list of manifest item IDs |
| Manifest | `<manifest>` → `<item id="..." href="..." media-type="...">` | Map of ID → file path + media type |

The spine gives reading order as a list of manifest item IDs. Resolve each ID against the manifest to get the actual XHTML file path relative to the OPF directory.

**Step 4 — Parse the table of contents**

Epub 2 and epub 3 use different TOC formats. Handle both:

- **Epub 3:** look for a manifest item with `properties="nav"`. Parse its XHTML for `<nav epub:type="toc">` → `<ol>` → `<li>` entries. Each entry has an `<a href="...">` and text content.
- **Epub 2:** look for a manifest item with `media-type="application/x-dtbncx+xml"`. Parse its `<navMap>` → `<navPoint>` entries. Each has a `<navLabel><text>` and a `<content src="...">`.

If neither is present, synthesise a TOC from the spine: "Chapter 1", "Chapter 2", etc. Better than crashing.

**Output — the parsed book struct:**

```swift
// The complete parsed representation of an epub file.
// This is what the parser hands back — everything downstream needs lives here.
struct ParsedEpub {
    let title: String
    let author: String
    let language: String                  // e.g. "en", "fr" — used for RTL detection
    let coverImageURL: URL?               // absolute path in the unzipped temp directory
    let spine: [SpineItem]                // ordered reading sequence
    let tocEntries: [TocEntry]            // table of contents
    let manifestItems: [String: ManifestItem]  // id → item, for asset lookup

    struct SpineItem {
        let id: String
        let href: String                  // path relative to OPF directory
        let absoluteURL: URL             // resolved absolute path in temp directory
    }

    struct TocEntry {
        let title: String
        let href: String                  // may include fragment: "chapter03.xhtml#section2"
        let children: [TocEntry]         // nested entries for hierarchical TOCs
    }

    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let absoluteURL: URL
    }
}
```

**Error handling:**

The parser throws typed errors rather than returning optionals. A partially-parseable epub is better than a crash — if the TOC is missing, synthesise it; if the cover is missing, return nil for that field; only throw if the epub is genuinely unreadable (no `container.xml`, no OPF, no spine).

```swift
enum EpubParserError: Error {
    case unzipFailed
    case containerXmlNotFound
    case opfNotFound
    case spineEmpty           // an epub with no readable chapters is unreadable
}
```

**Epub 2 vs epub 3 compatibility:**

The parser handles both transparently. The structural differences are: TOC format (NCX vs nav document — handled in Step 4), and cover image declaration (handled in Step 3). Everything else — container.xml, OPF structure, spine format — is identical between epub 2 and epub 3.

**What the parser does NOT do:**

- It does not render anything. Rendering is WKWebView's job.
- It does not paginate. That happens after WKWebView renders the chapter.
- It does not manage reading position. That is SwiftData + the Sync Engine.
- It does not stream chapters on demand. The full spine is parsed once at book-open time; individual chapter XHTML is loaded by WKWebView from the temp directory as needed.

**Temp directory lifetime:**

The unzipped epub lives in a temp directory for the duration of a reading session. It is created when a book is opened and deleted when the book is closed or the app goes to background. On next open, it is unzipped again. This keeps storage usage predictable and avoids managing a persistent extracted-epub cache.

### 3.3 CSS Injection Strategy

User preferences are applied using two complementary mechanisms to eliminate the flash of unstyled content (FOUC):

**Primary: `WKUserScript` at document start**

When the WKWebView is configured (at setup time, or whenever settings change), a `WKUserScript` is registered with `injectionTime: .atDocumentStart`. This causes the user preference CSS to be injected into the page's `<head>` before any epub HTML or CSS is parsed. The epub's own styles are overridden before they are ever applied — no flash.

```swift
func buildUserScript(from settings: ReaderSettings) -> WKUserScript {
    let css = buildUserPreferencesCSS(from: settings)
    // JSON-encode the CSS string to safely embed it as a JS string literal
    let encodedCSS = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    let js = """
        var style = document.createElement('style');
        style.id = 'codex-user-prefs';
        style.innerHTML = \(encodedCSS);
        document.head.appendChild(style);
    """
    return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
}
```

When the user changes a setting (e.g., drags the font size slider live), a follow-up `evaluateJavaScript` call updates the existing style element in-place — no page reload required:

```javascript
document.getElementById('codex-user-prefs').innerHTML = {{NEW_CSS}};
```

**The CSS content being injected:**

```css
html, body, p, div, span, li, td, th {
    font-size: {{USER_FONT_SIZE}}px !important;
    font-family: '{{USER_FONT_FAMILY}}', serif !important;
    line-height: {{USER_LINE_SPACING}} !important;
    letter-spacing: {{USER_LETTER_SPACING}}px !important;
    text-align: {{USER_TEXT_ALIGNMENT}} !important;
}
body {
    padding: {{TOP}}px {{RIGHT}}px {{BOTTOM}}px {{LEFT}}px !important;
    background-color: {{THEME_BG}} !important;
    color: {{THEME_TEXT}} !important;
}
p {
    margin-bottom: {{USER_PARAGRAPH_SPACING}}em !important;
}
```

**Paragraph spacing is injected separately on `p` elements** and always applied with `!important`, overriding any epub CSS that sets `margin` or `margin-bottom` to zero. This ensures the user's preference wins regardless of how the epub is encoded. Default value: 0.8em. See §2.8 for the full paragraph spacing spec and rationale.

Values are substituted from the user's current `ReaderSettings` object before building the script. Settings change → script is rebuilt → `userContentController.removeAllUserScripts()` + add the new script + reload if necessary, or use `evaluateJavaScript` for live preview.

**Theme colour values:**

| Theme | Background | Text |
|---|---|---|
| Light | `#FFFFFF` | `#1C1C1E` |
| Dark | `#1C1C1E` | `#F2F2F7` |
| Sepia | `#F5EDD6` | `#3B2A1A` |

These values are defined as constants in `ReaderTheme.swift` and are not hardcoded in the injection string.

### 3.4 Annotation Injection Hook

After user CSS is applied and the chapter is fully rendered, the Rendering Engine calls into the Annotation System to inject highlight overlays and margin markers. This is a post-render hook — annotations must sit on top of the final styled content, not beneath it.

The hook fires in the `webView(_:didFinish:)` delegate callback, after the user script has already run:

```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // 1. Annotation injection (must run after user CSS is applied)
    annotationSystem.injectAnnotations(for: currentChapterHref, into: webView)
    // 2. Pagination calculation (must run after final layout)
    paginationEngine.recalculate(for: webView)
}
```

The Annotation System is responsible for the actual JavaScript that creates highlight spans and margin markers. The Rendering Engine provides the hook and the `WKWebView` reference. The two modules stay decoupled — the Rendering Engine does not know the details of annotation rendering.

---

## 4. Reader View UI

### 4.1 Layout and Reader Chrome

The reader view is full-screen. There are two distinct chrome systems with different invocation models and different jobs.

---

**Chrome System 1 — Title and Page Metadata (tap to toggle)**

Tapping anywhere in the main reading area (not the left/right page-turn edges, not the bookmark ribbon) toggles the title strip and page metadata display. This is Apple's model and it works — no need to reinvent it.

- **Hidden state (reading mode):** only the bookmark ribbon (§4.7) is visible on the page. The page stack edges (§2.9) provide passive book-level progress. The reading surface is clean.
- **Shown state (tap to reveal):** a slim title strip appears at the top of the page (not a full navigation bar — see below) and a metadata strip appears at the bottom. Both fade in and out with a short opacity transition. Tapping again hides them.

**Title strip (top, tap-toggled):**
A single line showing the book title or chapter title (user's choice, configurable). Minimal — just text on the reading surface, no background bar. In skeuomorphic mode the text sits just inside the top margin.

**Metadata strip (bottom, tap-toggled):**
A single line of reading position information. What appears here is configurable via Advanced Settings → Reading → Metadata Display (see §4.5). Default elements: `Chapter N of M  ·  Page X of Y  ·  Y − X pages remaining in chapter`.

Pages remaining in the chapter is the most practically useful metric — it tells you whether you can finish the chapter before you have to put the book down. Book-level progress is communicated passively by the page stack edge depth (§2.9) rather than by a number or bar.

---

**Chrome System 2 — Options Panel (invocation TBD)**

Accessing the TOC, bookmarks list, annotation review, typography settings, and book sharing brings up a **floating panel** — not a full-screen sheet, not a nav bar that replaces the reading surface. The book remains partially visible behind it. The panel is dismissed by tapping outside it or swiping it away.

**What the panel contains:**
- Table of Contents
- Bookmarks, Highlights & Notes (annotation review)
- Reader Settings (Aa — typography panel)
- Share Book…
- Book Details

**Invocation mechanism: open question.** Several candidates, each with trade-offs. To be decided — possibly informed by user research:

| Option | Feel | Trade-offs |
|---|---|---|
| Swipe from left edge | Natural on iPad; feels like opening a cover | Conflicts with system back gesture on iPhone unless distance threshold is tuned carefully |
| Persistent small icon on page | Always discoverable, like the bookmark ribbon | Adds another permanent element to the clean reading surface |
| Long press on title strip (when shown) | Logical — the title area is already the "book identity" zone | Requires System 1 chrome to be visible first; two steps |
| Two-finger tap anywhere on page | Clean, no permanent icon needed | Discoverability problem — invisible gesture |
| Swipe up from bottom edge | Feels natural on iPhone | Conflicts with home gesture on iPhone X+ unless from within the safe area |

**Recommendation for investigation:** a persistent small icon — roughly the same visual weight as the bookmark ribbon — in a fixed corner position. Always visible, always one tap away, never conflicts with any gesture. Exact position and design to be decided during visual development. This parallels the bookmark ribbon approach and creates a consistent language: small persistent icons on the page for quick actions, tap-toggled strips for reading metadata.

---

**Persistent on-page elements (always visible, regardless of chrome state):**
- Bookmark ribbon (§4.7) — top-right corner (or leading edge in skeuomorphic mode)
- Options panel icon (design TBD) — one corner of the page

**Tap zones:**
- Left edge (~35%) → previous page
- Right edge (~35%) → next page  
- Centre (~30%) → toggle title/metadata strips (System 1)
- Persistent icons → their specific actions

**Status bar:** visible and dimmed by default. Full immersive mode (hidden status bar) is toggled from the options panel. When hidden, time and battery can optionally be shown in the metadata strip — configurable in Advanced Settings (§4.5).

**Gestures:**
- Swipe left / right → page turns (with finger-following in Curl and Slide modes)
- Long press on text → text selection
- System swipe from left edge → back to library (always works regardless of chrome state)

### 4.2 Reader Settings Panel

Accessible via the **Reader Settings** item in the options panel (§4.7 Chrome System 2). Opens as a bottom sheet with:

**Surface controls** (visible immediately — the things most readers will touch):
- Font size slider (with live preview — the page behind the sheet updates as the user drags)
- Font family picker
- Line spacing slider
- Theme selector (Light / Dark / Sepia) with colour swatches
- Page turn style selector
- Margin sliders (left/right linked by default; unlinkable via a small toggle for independent control)

**"More Typography…" row** at the bottom of the panel (tap to expand in-place):
- Letter spacing slider (-2px to +4px in 0.1px steps)
- Text alignment toggle (Left / Justified)
- "Use book fonts" toggle (when on, Codex respects the epub's embedded or referenced fonts; font family picker is disabled)

All changes are applied live to the page behind the sheet. No confirmation step.

**Per-book overrides toggle** — at the top of the settings panel, a small segmented control:

> **Applies to:** [My Defaults] [This Book]

- **My Defaults** (selected by default): any change updates the user's global `ReaderSettings`. All books that don't have per-book overrides for that setting will change immediately.
- **This Book**: any change creates or updates a `BookReaderOverrides` entry for the current book only. Global defaults are untouched.

When a book has active per-book overrides, the panel opens with "This Book" pre-selected and shows a subtle indicator: "Custom settings active for this book." A **Clear book settings** button in the "More Typography…" section removes all per-book overrides and reverts to global defaults.

The typical workflow Scott uses: open a book, find the font size or leading is off for this specific text, switch to "This Book", adjust, and keep reading. His global defaults remain what he set them to be for everything else.

### 4.3 Table of Contents

- Accessible via the **Table of Contents** item in the options panel (§4.7 Chrome System 2).
- Displays the epub's navigation document as a hierarchical list.
- Tapping a TOC entry navigates to that chapter/section.
- Current position is highlighted in the TOC.

### 4.4 Progress Display

The reading surface has two progress systems that serve different purposes and are independent of each other.

**Passive progress — page stack edges (§2.9):** when the page stack is enabled, book-level progress is communicated visually at all times through the apparent thickness of the fanned page edges. No number, no bar, no chrome required. You feel where you are in the book the same way you feel it when holding the physical object.

**Active metadata — tap-toggled strip (System 1 from §4.1):** tapping the reading surface reveals a metadata strip at the bottom of the page. This is where precise chapter-level information lives. What appears in the strip is configurable (see §4.5 Advanced Settings), independently for the two display modes:

- **Mode A — metadata strip visible (chrome shown):** default elements: `Chapter N of M  ·  Page X of Y  ·  Y − X pages remaining in chapter`
- **Mode B — strip hidden (clean reading mode):** no persistent indicator. Passive page stack handles it.

Pages remaining in the current chapter is the most practically useful metric — it tells you whether you can finish before you need to stop. Overall book progress is handled by the page stack edges.

**Optional metadata elements** (each independently togglable per mode in Advanced Settings):

| Element | Example | Useful for |
|---|---|---|
| Chapter position | Page 7 of 24 | Knowing where you are in the chapter |
| Pages remaining in chapter | 17 pages left | Planning your reading session |
| Chapter indicator | Chapter 3 of 12 | Context in the overall book |
| Book progress % | 31% | Precise overall progress |
| Reading time remaining | ~3h 20m left | Session planning |
| Time remaining in chapter | ~18m | Immediate session planning |
| Clock | 9:41 PM | When status bar is hidden in full immersive mode |

**Progress scrubber:** lives at the top of the options panel (§4.7), always the first thing visible when the panel opens. A full-width draggable slider — drag anywhere on the track to jump to that position in the book instantly. As the user drags, a floating label above the thumb shows the chapter name at that position. Release to navigate. This is a first-class navigation tool, not an afterthought. Kindle's absence of any scrubber is a well-known frustration; Codex treats fast navigation as a core requirement.

**Auto-bookmark on scrub:** the moment the user touches the scrubber thumb, Codex silently creates a bookmark at the current reading position before any navigation happens. This means the user can always jump back to exactly where they were before they started exploring. The auto-bookmark is distinct from a manual bookmark — it does not appear in the main bookmarks list, but a "Return to your previous position" prompt appears once after a scrub jump (similar to the "You were on page X" prompt in some readers). If the user navigates back manually, the prompt clears. Togglable in Advanced Settings (default: on).

**Reading speed and time estimation:** Codex tracks words read per session to build a personal reading speed estimate. Default when no history exists: 250 wpm. Self-corrects over the first few reading sessions. Shown as approximate ("~3h 20m"), intentionally rounded. Can be turned off in Advanced Settings for users who find time-remaining displays anxiety-inducing.

**"Go to page" is not a v1 feature.** Epub pages are derived from screen geometry and font size — there is no stable absolute page number. Chapter and position references are more meaningful.

### 4.6 First-Open Typography Prompt

The first time a newly ingested book is opened, Codex shows a **typography choice overlay** before the book begins. The goal is to give the reader one informed moment to decide how this specific book will look — respecting that a publisher or editor may have made intentional typographic choices worth preserving, while also making it easy to apply personal defaults or customise on the spot.

This prompt appears **only once per book**, on first open. It is skipped entirely if the book has been opened before (including after re-ingestion when reading history is retained).

#### The Three Choices

| Choice | Label | What it does |
|---|---|---|
| **A** | Publisher's Style | Codex renders the book using the epub's own CSS and fonts, with no user overrides. Sets `typographyMode = .publisherDefault`. |
| **B** | My Defaults | Codex applies the user's global `ReaderSettings` fully. Sets `typographyMode = .userDefaults`. |
| **C** | Customize | Opens the in-reader typography panel in "This Book" mode. Whatever the user saves sets `typographyMode = .custom` with their `BookReaderOverrides`. |

The choice is stored permanently in the book's reading history and survives re-ingestion. It can be revisited at any time via **Book Detail → Reset typography for this book**, which re-triggers the prompt.

#### Finding the Preview Excerpt

The overlay shows real text from the book — not a title page, not a copyright notice, but the first actual prose content. The lookup order:

1. **epub3 `landmarks`** — look for a `bodymatter` or `text` start point in the navigation document.
2. **epub2 `guide`** — look for a `text` reference.
3. **Heuristic fallback** — scan linear spine items in order; skip items whose filename matches common non-content patterns (`cover`, `titlepage`, `copyright`, `toc`, `colophon`, `dedication`); take the first item with > 200 words of visible text content.
4. **Last resort** — first linear spine item regardless of content.

The excerpt shown is approximately the first 250–350 words of the located page. This is enough to convey typographic character without requiring the user to scroll.

#### The Comparison UI

**On iPhone** (narrow screen — side-by-side impractical):

A modal sheet occupies ~85% of screen height. The excerpt is displayed in a scrollable pane in one of the two styles. A prominent segmented control at the top — `[Publisher's Style] [My Style]` — toggles the live preview between styles A and B with a smooth crossfade transition. The user can flip back and forth to compare. At the bottom: three buttons — **Use Publisher's Style** / **Use My Defaults** / **Customize…**

**On iPad** (wide screen — comparison works naturally):

The modal uses a side-by-side split layout. Left pane: Publisher's Style (labelled "A — Publisher's Style"). Right pane: My Defaults (labelled "B — My Defaults"). Both render simultaneously from the same excerpt. The user can scroll both panes together (linked scroll). At the bottom, centred: **Use Publisher's Style** / **Use My Defaults** / **Customize…**

Both layouts include a small **"Skip for now"** option (small text, not a prominent button) that dismisses the prompt and defaults to "My Defaults" without permanently storing a choice — meaning the prompt will reappear next time the book is opened. This is for users who open the wrong book by accident or aren't ready to decide.

#### The Customize Path — Panel Detail

When the user taps **Customize…**, the overlay transitions into the in-reader typography panel, pre-configured for this specific book. The panel opens in "This Book" mode automatically.

**Starting point:** The panel initialises from the publisher's rendered values, not the user's global defaults. Before opening the panel, Codex queries the epub's computed styles from the WKWebView via JavaScript (`window.getComputedStyle(document.body)`) to extract the actual rendered font size, line height, margins, and letter spacing. These become the panel's initial values. The user is adjusting *from* the publisher's choices, not from a blank slate.

**Starting point selector** — at the top of the panel, a segmented picker:

> **Start from:** [Publisher's Style ▾]

Tapping opens a short menu of starting points:
- **Publisher's Style** — epub's computed values (default when arriving from the prompt)
- **My Defaults** — the user's global `ReaderSettings`
- **[Series Name], Book N** — available only when the current book is part of a series and an earlier book in that series has been read with custom settings. Uses the `BookReaderOverrides` from the highest previously-read entry in the series. If multiple earlier books exist, only the most recently-read one is offered. This is the primary mechanism for keeping a consistent reading experience across a multi-volume series.

Switching starting point resets the panel's values immediately (with a brief animation) but does not commit anything until the user taps **Done**.

**Quick-apply switches** — below the starting point picker, before the detailed sliders, a row of individual toggle switches. Each switch applies one aspect of the user's global defaults to this book. All off by default when starting from publisher style:

| Switch | When toggled on | When toggled off |
|---|---|---|
| Font Size → [N]pt | Applies global `fontSize` to this book | Keeps publisher's size |
| Font Family → [Name] | Applies global `fontFamily` | Keeps publisher's font |
| Margins → [N]pt | Applies global margins | Keeps publisher's margins |
| Line Spacing → [N×] | Applies global `lineSpacing` | Keeps publisher's leading |
| Letter Spacing → [N]px | Applies global `letterSpacing` | Keeps publisher's tracking |

The current global default value is shown inline on each switch label (e.g., "Font Size → 18pt") so the user knows exactly what they're toggling on. Toggling a switch on immediately updates the live preview behind the panel. Toggling it off reverts that property to the publisher's value.

Below the quick-apply switches, the **detailed slider controls** are always accessible for fine-tuning any individual property. If a quick-apply switch is off but the user manually moves the corresponding slider, the switch flips on automatically (they've now overridden that property). If a slider is moved back to the publisher's value, the switch flips off.

Tapping **Done** saves all active overrides as `BookReaderOverrides`, sets `typographyMode = .custom`, dismisses the panel, and opens the book.

#### Publisher Mode — What Gets Overridden and What Doesn't

When `typographyMode = .publisherDefault`, Codex deliberately does not inject its user CSS overrides. The epub's own fonts, sizes, margins, and layout are fully respected. However, two user preferences always apply regardless of mode — because the epub's CSS cannot anticipate the reader's device or visual environment:

- **Theme** (background and text colour): the user's light/dark/sepia theme is applied so the background matches the rest of the app and dark mode works correctly.
- **Minimum font size floor**: a very conservative floor (~10pt) prevents any epub from rendering text genuinely unreadable due to a CSS mistake. This is a safety net, not a ceiling.

Everything else — font family, size, margins, leading, letter spacing — is left entirely to the epub's CSS in publisher mode.

### 4.7 Navigation Controls — Bookmark, TOC, and the More Menu

#### One-Tap Bookmark

A bookmark ribbon is permanently visible in the corner of the reading page — not part of the navigation chrome, not hidden when the nav bars are hidden. It is always there, passive and unobtrusive when empty, immediately recognisable when filled.

**Visual:** a ribbon shape with a V-cut at the bottom, like a physical bookmark tab hanging from the top of a page. This is the classic hardcover bookmark ribbon shape — no explanation needed.

- **Outline only** (default state): the ribbon is rendered as a thin outline in a neutral colour. No bookmark exists on this page.
- **Solid red** (bookmarked state): the ribbon fills solid red. A bookmark exists at this exact position.
- The transition between states is immediate on tap — no animation delay, no dialog, no confirmation. A subtle haptic confirms.

**Position:**
- Standard mode: top-right corner of the reading area, just inside the margin.
- Skeuomorphic mode (page stack edges active): the ribbon moves to the top of the leading edge — near the spine, as it would be on a physical book. A physical bookmark hangs from the spine end of a page, not the outer corner.

**Adding a label:** long-pressing the ribbon (in either state) opens a small inline text field directly below the ribbon. Label is optional. Unlabelled bookmarks display the chapter name and position in the bookmarks list. Labelled bookmarks show the user's text.

**A note on "current page":** in paginated modes, the bookmark records the chapter href and character offset of the first visible character on the current page. In scroll mode, it records the scroll position as a percentage within the chapter. Consistent with how all reading positions are stored throughout the app.

**Navigation bar:** the ☆ bookmark icon previously described in the navigation bar is removed — the ribbon on the page handles creation and deletion. The navigation bar is correspondingly simplified (see §4.1).

#### Options Panel Contents

The options panel (floating, invocation TBD — see §4.1 Chrome System 2) contains:

| Item | Action |
|---|---|
| **Progress slider** | A full-width draggable slider showing position in the current book. Drag to jump anywhere instantly. As the slider moves a floating label shows the chapter name at that position. This is a real scrubber, not a decorative indicator — it is the primary navigation mechanism for jumping around a book. Kindle's lack of this is a long-standing frustration; Codex has it. |
| **Current chapter info** | Chapter title, chapter number, and page count for the current chapter displayed above the slider for context. |
| **Table of Contents** | Hierarchical navigation from the epub's navigation document. Current position highlighted. Tap an entry to navigate. |
| **Bookmarks, Highlights & Notes** | Opens the annotation review screen (Annotation System §4). Filtered tabs: All / Highlights / Notes / Bookmarks. |
| **Reader Settings** | Opens the typography panel (§4.2) — Aa controls |
| **Share Book…** | Sends the epub file via the iOS system share sheet |
| **Book Details** | Opens the Book Detail view from the Library Manager |
| **Full Screen** | Toggles full immersive mode (hides system status bar) |

The panel is a floating overlay — the book remains partially visible behind it. Dismissed by tapping outside or swiping it away. On iPad it may anchor to the side of the screen; on iPhone it rises from the bottom as a compact sheet that doesn't obscure the top of the page.

State-specific options (e.g., "Force Re-upload" when an iCloud issue is detected) live in Book Details, not in this panel.

### 4.8 Text Selection — Look Up, Search Web, and Annotations

When the user long-presses on text in the reader, the standard iOS text selection UI activates: selection handles appear, the magnifier glass is shown during adjustment, and when the selection is finalised a callout bar appears above the selected text.

**Codex extends — but does not replace — the standard iOS callout.** Our custom actions are prepended; all system-provided actions are preserved in their standard positions.

**Callout bar action order:**

`Highlight · Note · Copy · Look Up · Search Web · Translate · Share · ···`

| Action | What it does | Implementation |
|---|---|---|
| **Highlight** | Creates a highlight annotation using the last-used colour | Custom `UIAction` added via `UIEditMenuInteraction` (iOS 16+) |
| **Note** | Opens the note editor; creates a highlight+note annotation | Custom `UIAction` |
| **Copy** | Copies selected text to the pasteboard | Standard iOS — preserved |
| **Look Up** | Opens the iOS native dictionary/reference/Wikipedia lookup panel | Standard iOS — preserved. Uses the system lookup mechanism. **This is what Apple Books recently removed from their reader. Codex does not remove it.** |
| **Search Web** | Opens Safari with selected text as a search query | Standard iOS — preserved. Apple has removed this action inconsistently across iOS versions and app contexts. Explicit testing required on each target iOS version to confirm it appears reliably. If it disappears due to an iOS change, investigate and restore via `UIAction` if a supported path exists. |
| **Translate** | iOS system translation panel (iOS 14+) | Standard iOS — preserved |
| **Share** | iOS share sheet with selected text (see §4.9) | Standard iOS Share with attribution appended |
| **···** | Overflow for additional system-provided items | Standard iOS |

**Implementation note:** `UIEditMenuInteraction` (iOS 16+) is the modern API for customising the callout menu in a `UIView`/`WKWebView`. Custom actions are added via the `willPresentMenuWithAnimator:` delegate method. The goal is additive — we do not call any API that suppresses or replaces the system's default items. If Apple adds new system actions in future iOS versions, they will appear automatically.

**Look Up in detail:** iOS's "Look Up" opens the system dictionary panel using the selected text. In a `WKWebView`, this action is provided by the system if the web view's selection behaviour is not overridden. Codex must not disable the WKWebView's `selectionGranularity` or intercept the JavaScript `selectionchange` event in a way that blocks system lookup. The selection interaction is permitted to behave naturally — we only add our custom actions on top.

### 4.9 Text Sharing — Share Sheet, Attribution, and No Artificial Limits

When the user selects text and taps **Share** in the callout, the iOS share sheet opens with the selected text as the share payload.

**Attribution:** by default, Codex appends an attribution line to shared text:

> *[Selected text]*
>
> — [Book Title], [Author]

This follows the common convention for quoted excerpts and gives the passage its proper context. Attribution can be turned off in Advanced Settings (default: on). When off, only the raw selected text is shared.

**No artificial limits.** Codex does not impose character limits on text sharing. The user owns these books (DRM-free only). They may share as much text as they wish. There is no "sharing limit" warning, no counter, no gate.

**Additional share actions** available as activity extensions in the share sheet:
- **Copy with Citation** — copies text + attribution + chapter/position reference to clipboard in a clean format (e.g., *"Quote." — Book Title, Chapter 3, Author*)
- **Add to Note** — if a Notes.app extension is installed; standard iOS share extension, not custom-built

**Share format for the full export option** (sharing an entire annotation review as rich text, plain text, or markdown) is specified separately in the Share & Transfer directive (Module 5).

### 4.5 Advanced Settings (App Settings → Reading → Advanced)

In keeping with the project philosophy (§6.4 of the overall directive), every tunable value in the Rendering Engine has a setting home. The following belong in the Advanced section of Reading Settings — accessible but not in the way of typical users:

| Setting | Description | Default |
|---|---|---|
| **Font size minimum** | Lower bound of the font size slider (personal preference — not a hard app limit) | 8pt |
| **Font size maximum** | Upper bound of the font size slider | 72pt |
| **Publisher mode safety floor** | Minimum font size applied in publisher mode only, as a safety net for broken epub CSS | 10pt |
| **Match Surroundings threshold** | Screen brightness % below which Dark mode activates in Match Surroundings mode | 30% |
| **Background warmth default** | Default position of the warmth slider (−100 = cool, 0 = neutral, +100 = warm) | 0 |
| **iPad orientation auto-switch** | Auto-switch to Scroll when rotating iPad from landscape to portrait | On |
| **iPad rotation lock** | Lock iPad to landscape for reading (disable rotation) | Off |
| **iPhone rotation lock** | Lock iPhone to portrait for reading | On |
| **Tap zone layout** | Resize the left/right tap areas for page turns relative to the centre tap zone for chrome toggle | 35% / 30% / 35% |
| **Status bar in reader** | Show / Hide (full immersive) | Show |
| **Show time in reader chrome** | When status bar is hidden, show a small clock in the bottom bar | Off |
| **Show battery in reader chrome** | When status bar is hidden, show battery indicator in bottom bar | Off |
| **Metadata strip: chapter position** | Show "Page N of Y" in the tap-toggled metadata strip | On |
| **Metadata strip: pages remaining** | Show "Y − X pages remaining in chapter" | On |
| **Metadata strip: chapter indicator** | Show "Chapter N of M" | Off |
| **Metadata strip: book progress %** | Show overall percentage | Off |
| **Metadata strip: time remaining** | Show reading time estimate | On |
| **Metadata strip: time scope** | Whole book / Current chapter | Chapter |
| **Metadata strip: clock** | Show clock (useful when status bar hidden) | Off |
| **Title strip: show book title or chapter title** | Which title to show in the tap-toggled title strip | Chapter title |
| **Auto-bookmark on scrub** | Silently save current position before any scrubber jump, with a "return to previous position" prompt after | On |
| **Reading speed baseline** | Manual override for wpm (auto-calculated from session history otherwise) | Auto |
| **Fixed-layout epub handling** | Zoom-and-pan (default) or auto-fit to screen width | Zoom-and-pan |
| **FOUC protection timeout** | Max milliseconds to suppress display waiting for user script injection before showing content anyway | 150ms |
| **Annotation injection timeout** | Max milliseconds to wait for annotation overlay injection before giving up and showing the page without them | 100ms |
| **WKWebView memory limit** | Number of adjacent chapter WKWebView instances to keep warm in memory | 3 (current + 1 before + 1 after) |
| **Reset all reader settings** | Restores all typography and layout settings to defaults | — |

---

## 5. Performance Requirements

- Chapter load time (from page turn to rendered text visible): < 300ms on an iPhone 12 or newer.
- CSS injection must not produce a visible flash of unstyled content (FOUC). Inject styles before the WKWebView navigation commits where possible, or suppress display until injection is complete.
- Pagination calculation must not block the main thread. Run in a background task and update UI when complete.
- Memory: the renderer should not hold more than 3 chapter WKWebView instances in memory at once (current, previous, next). Others are unloaded and reloaded on demand.

---

## 6. Accessibility

- All font size controls work in concert with iOS Dynamic Type. The user's chosen font size in Codex is independent of the system Dynamic Type setting.
- VoiceOver must be able to read the page content naturally. The WKWebView content must be semantically valid HTML.
- High contrast themes should be tested; consider an additional "High Contrast" theme option.
- Minimum tap target size: 44×44pt for all interactive elements.

---

## 7. Settings Data Model

### 7.1 Global Reader Settings

Stored in UserDefaults (or SwiftData) and synced via the Sync Engine. These are the user's personal defaults — applied to every book unless a per-book override exists.

```swift
struct ReaderSettings: Codable {
    var fontSize: CGFloat          // e.g., 18.0 (points)
    var fontFamily: String         // e.g., "Georgia"
    var useBookFonts: Bool         // false = always override with fontFamily
    var lineSpacing: CGFloat       // e.g., 1.4
    var paragraphSpacing: CGFloat  // e.g., 0.8 (em units) — margin-bottom on p elements; default 0.8em
    var letterSpacing: CGFloat     // e.g., 0.0
    var textAlignment: TextAlign   // .left | .justified
    var theme: ReaderTheme         // .light | .dark | .sepia
    var pageTurnStyle: PageTurn    // .curl | .slide | .scroll (fade was considered and dropped)
    var marginTop: CGFloat
    var marginBottom: CGFloat
    var marginLeft: CGFloat
    var marginRight: CGFloat
}
```

### 7.2 Per-Book Typography Mode

Each book has a `typographyMode` field (set by the first-open typography prompt, §4.6) that determines how the Rendering Engine treats that book's CSS. Stored in the `Book` SwiftData model. Synced via the Sync Engine.

```swift
enum BookTypographyMode: String, Codable {
    case publisherDefault  // Epub's own CSS fully respected; no user overrides injected
    case userDefaults      // User's global ReaderSettings applied in full
    case custom            // BookReaderOverrides merged with ReaderSettings (see §7.3)
}
```

Default value for newly ingested books before the first-open prompt is shown: `.userDefaults`. This means if a user somehow opens a book without seeing the prompt (edge case), they get their preferred settings rather than an unexpected epub rendering.

### 7.3 Per-Book Overrides

Stored in the `Book` SwiftData model (as a JSON-encoded blob or as individual optional columns). Only relevant when `typographyMode == .custom`. Synced via the Sync Engine alongside all other book metadata. All fields are optional — only fields the user has explicitly overridden for this book are set. Nil means "use the global default."

```swift
struct BookReaderOverrides: Codable {
    // Each field mirrors ReaderSettings but is Optional.
    // nil = "no override — use global preference"
    var fontSize: CGFloat?
    var fontFamily: String?
    var useBookFonts: Bool?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?  // nil = use global default (0.8em)
    var letterSpacing: CGFloat?
    var textAlignment: TextAlign?
    var theme: ReaderTheme?
    var pageTurnStyle: PageTurn?
    var marginTop: CGFloat?
    var marginBottom: CGFloat?
    var marginLeft: CGFloat?
    var marginRight: CGFloat?
}
```

### 7.4 Effective Settings — Merge at Render Time

Before injecting CSS, the Rendering Engine resolves the effective settings based on the book's `typographyMode`. The result is either a fully populated `ReaderSettings` to inject, or `nil` meaning "inject nothing — let the epub's own CSS stand."

```swift
// Returns the effective ReaderSettings to use for CSS injection.
// Returns nil when the book is in publisherDefault mode,
// which signals the Rendering Engine to skip user CSS injection entirely
// (except for theme background/text colour — those always apply).
func effectiveSettings(
    global: ReaderSettings,
    book: Book
) -> ReaderSettings? {
    switch book.typographyMode {

    case .publisherDefault:
        // Epub's own CSS is in charge. Return nil to skip user overrides.
        // Theme (background, text colour) and minimum font floor are still
        // applied separately — see the rendering path in §3.3.
        return nil

    case .userDefaults:
        // No per-book overrides. Global settings apply in full.
        return global

    case .custom:
        // Merge: global settings as base, per-book overrides on top.
        guard let overrides = book.typographyOverrides else { return global }
        return ReaderSettings(
            fontSize:      overrides.fontSize      ?? global.fontSize,
            fontFamily:    overrides.fontFamily    ?? global.fontFamily,
            useBookFonts:  overrides.useBookFonts  ?? global.useBookFonts,
            lineSpacing:   overrides.lineSpacing   ?? global.lineSpacing,
            letterSpacing: overrides.letterSpacing ?? global.letterSpacing,
            textAlignment: overrides.textAlignment ?? global.textAlignment,
            theme:         overrides.theme         ?? global.theme,
            pageTurnStyle: overrides.pageTurnStyle ?? global.pageTurnStyle,
            marginTop:     overrides.marginTop     ?? global.marginTop,
            marginBottom:  overrides.marginBottom  ?? global.marginBottom,
            marginLeft:    overrides.marginLeft    ?? global.marginLeft,
            marginRight:   overrides.marginRight   ?? global.marginRight
        )
    }
}
```

This function is called once per chapter load and whenever the user adjusts a setting in the reader panel. The nil return path is handled in the CSS injection logic: when `effectiveSettings()` returns nil, the `WKUserScript` is built with only theme background/text colour and the minimum font floor, leaving all other epub CSS intact.

---

## 8. Open Questions

- **ReadiumSDK vs custom parser:** ✅ **Decided.** Custom parser. See §3.2 for full spec.

- **Per-book typography overrides:** ✅ **Decided.** In scope for v1. All typography settings (font, size, margins, leading, etc.) support per-book overrides. Global preferences are always the starting baseline — epub encoding is irrelevant. Per-book overrides are user-initiated adjustments on top of those globals. The "My Defaults / This Book" segmented control in the reader settings panel is the UX mechanism. See §2.1 and §7 for full spec.

- **Epub 3 Media Overlays (read-aloud):** Out of scope for v1 but the architecture should not preclude it.

- **Fixed-layout epubs:** Some epubs (e.g., graphic novels, children's books) use fixed-layout format that cannot be reflowed. Codex should detect these and display them as-is (zoom/pan), but user typography overrides will not apply. A clear, friendly notice should be shown to the user when a fixed-layout epub is opened ("This book uses a fixed layout and cannot be restyled."). The default handler (zoom/pan vs auto-fit) is a setting in Advanced (§4.5).

- **Right-to-left language support:** Should be supported by the WebKit renderer natively but needs explicit testing. RTL also affects the tap-to-turn direction (swipe left = forward for LTR; swipe right = forward for RTL). Codex should auto-detect from epub language metadata.

- **In-reader text search (find in book):** No spec exists for searching within the book's text — a "find in page" / Ctrl+F equivalent. This is a commonly expected reading feature. WKWebView supports `WKWebView.find(_:configuration:completionHandler:)` (iOS 16+) which provides native find-in-page with match highlighting and navigation controls. Decision needed: v1 or v1.1? If v1, the options panel needs a Search item and the results UI needs specifying (likely a bottom bar showing "Match N of M" with prev/next navigation). Recommendation: include in v1 — it is low implementation cost via the native API and its absence would be conspicuous.

- **Options panel invocation mechanism:** How the user summons the floating options panel (TOC, bookmarks, annotations, settings, share) is undecided. Candidates are listed in §4.1. A persistent small icon (parallel to the bookmark ribbon) is the recommended starting point for investigation. Exact position, icon design, and gesture to be decided during visual development, potentially informed by user research.

---

*Module status: Directive substantially revised — reader navigation chrome fully specified, one-tap bookmark, text selection (Look Up / Search Web preserved), text sharing with attribution, skeuomorphic reader surface option, dark mode detection modes, page turn implementation detail, progress indicator with reading time estimate, and time/status bar display options all added. Parser decision still requires technical spike.*  
*Last updated: April 2026*
