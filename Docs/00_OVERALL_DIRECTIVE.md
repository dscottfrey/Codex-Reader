# Codex — Overall Project Directive
**Working Title:** Codex  
**Naming Note:** "Codex Books" exists on the App Store (a scanning/catalog tool). The name Codex should be treated as a working title. Final naming decision to be made before App Store submission. Alternatives worth considering: Folio, Verso, Quire, Leaf, Recto.

**Platforms:** iOS 17+ and iPadOS 17+  
**Primary Framework:** SwiftUI (UIKit bridged where rendering precision demands it)  
**Distribution:** App Store (primary target), TestFlight (beta), personal sideload via Xcode / AltStore  
**Development Model:** AI-assisted, directed by non-developer owner  

---

## 1. Vision

Codex is a clean, reliable, user-first epub reader for iPhone and iPad. It exists as a direct replacement for Apple's Books app, which has become frustrating to use due to arbitrary rendering restrictions, unreliable sync, poor ingestion options, and general feature regression over time.

Codex gives readers complete control over how their books look, where their books live, and how their books move between devices. It does not try to be a bookstore. It does not gamify reading. It does not try to sell anything. It reads books, beautifully and reliably.

---

## 2. Goals

- **Full rendering control.** The user — not the epub file, not the app — decides font size, font family, margins, and page turn style. No arbitrary ceilings. No automatic style switching.
- **Frictionless ingestion.** Books come in from wherever the user has them: a personal Calibre server via OPDS, the iCloud Drive Inbox folder, AirDrop, the system share sheet, or the Files app. If there's an epub, Codex can receive it. One tap, book on shelf.
- **Your books are your files.** Epub files live in iCloud Drive in a folder the user can see, browse, and manage like any other files. They are not locked inside the app. They are not held hostage to a sync service. If iCloud is broken, there is always a manual path to get a book onto the device and open it. **Codex never holds a book hostage to iCloud.**
- **Reliable, silent sync.** Reading position, bookmarks, highlights, and notes sync across all the user's devices via iCloud (CloudKit) without the user having to think about it, trigger it, or troubleshoot it. When sync fails, the app degrades gracefully — it never blocks reading.
- **DRM-free sharing.** The user can send a DRM-free epub to another device or another person via AirDrop or the iOS system share sheet. No friction, no warnings theater.
- **Honest annotations.** The user can highlight text, write notes, and bookmark pages. All annotations can be reviewed in one place and exported as rich text, plain text, or markdown.
- **Permanent reading history.** Reading position, annotations, and bookmarks are retained forever — independent of whether the epub file is currently on the device. Re-ingesting a book that was previously read offers an informed resume prompt, not a silent reset.
- **Portable data ownership.** All reading data — positions, annotations, bookmarks, metadata — can be exported as a standard JSON file the user owns completely, stored wherever they choose, independent of Apple or any cloud service. If CloudKit disappears tomorrow, nothing is lost.
- **Zero enshittification.** No badges, no reading streaks, no "Reading Goals," no store integration, no upsells, no social features unless explicitly requested in a future version.

---

## 3. Anti-Goals

The following are explicitly out of scope and should not be architected for, even as optional future hooks, unless a deliberate decision is made to revisit them:

- No DRM support (FairPlay or Adobe). Codex is for DRM-free epubs only.
- No built-in bookstore or purchase flow.
- No social/community reading features (Goodreads-style integration, friend activity, etc.).
- No gamification (reading streaks, badges, goals, statistics dashboards).
- No PDF rendering (may be revisited in a future version but is not in scope for v1).
- No audiobook support.
- No cloud library hosting — Codex manages files on-device and via iCloud Drive; it is not a server-based service.

---

## 4. Technical Stack

| Concern | Choice | Rationale |
|---|---|---|
| UI Framework | SwiftUI | Modern, adaptive, well-suited for iOS/iPadOS split-screen and Dynamic Type integration |
| Epub Rendering | WKWebView (WebKit) inside a SwiftUI wrapper | Industry standard for epub rendering on Apple platforms; gives full CSS/HTML control |
| Epub Parsing | FolioReaderKit or ReadiumSDK (evaluate) or custom Swift parser | Determines how epub spine, manifest, and metadata are read |
| Data Persistence | SwiftData | Local storage of library metadata, annotations, reading position |
| Sync | SwiftData + ModelContainer CloudKit sync (private database) | Minimal boilerplate; automatic iCloud sync built into the framework |
| File Management | FileManager + UIDocumentPickerViewController | Standard iOS file access APIs |
| Networking (future) | Network framework (local HTTP server) | Reserved for v1.1 Codex-to-Codex direct transfer (MultipeerConnectivity); not in v1 scope |
| Minimum Deployment Target | iOS 17.0 / iPadOS 17.0 | Unlocks SwiftData, SwiftUI 5, and native CloudKit sync integration |

---

## 5. Module Architecture

Codex is built as a set of discrete, independently developed modules. Each module has its own directive document. Modules communicate through well-defined interfaces (protocols/services) and should not have tight internal dependencies on each other.

```
Codex App
├── Module 1: Rendering Engine       (core reading experience)
├── Module 2: Ingestion Engine       (getting books in)
├── Module 3: Library Manager        (organizing and browsing books)
├── Module 4: Sync Engine            (iCloud sync of state and metadata)
├── Module 5: Share & Transfer       (sending books and notes out)
└── Module 6: Annotation System      (highlights, notes, bookmarks)
```

Each module has a corresponding directive file:

| File | Module |
|---|---|
| `01_RENDERING_ENGINE.md` | Rendering Engine |
| `02_INGESTION_ENGINE.md` | Ingestion Engine |
| `03_LIBRARY_MANAGER.md` | Library Manager |
| `04_SYNC_ENGINE.md` | Sync Engine |
| `05_SHARE_TRANSFER.md` | Share & Transfer |
| `06_ANNOTATION_SYSTEM.md` | Annotation System |

---

## 6. Development Philosophy

These principles apply to every line of code written for Codex, across all modules. They are not aspirational — they are requirements. Any implementation that violates them should be refactored before moving on.

### 6.1 Occam's Razor — Simplest Solution That Works

When there are two ways to solve a problem, choose the simpler one. Always.

- If Apple's SDK already does something, use it rather than building a custom version.
- If a problem can be solved with 20 lines of straightforward code or 100 lines of clever code, write 20 lines.
- Avoid "future-proofing" that adds complexity now for benefits that may never be needed. Build for what the app does today. Refactor when requirements actually change.
- When evaluating a library or approach, the question is: "Is this the simplest thing that will work reliably?" — not "Is this the most powerful option?"
- Clever code is a liability. Simple code is an asset.

### 6.2 Heavy Code Comments — Code the Owner Can Read

Every file should be legible to a non-developer who is willing to read carefully. This means:

- **File header comments:** Every Swift file begins with a block comment explaining what this file is, why it exists, and how it fits into the module it belongs to.
- **Function/method comments:** Every function has a plain-English comment above it explaining what it does, what goes in, and what comes out — before the function signature.
- **Inline comments:** Any line or block of code that isn't immediately obvious to a non-developer gets an inline comment. When in doubt, comment.
- **Decision comments:** When a specific approach was chosen over an alternative (and it's not obvious why), a comment explains the reasoning. Example: `// We copy the file here rather than using a security-scoped bookmark because the bookmark becomes invalid after the app restarts.`
- **Section dividers:** Long files use `// MARK: - Section Name` dividers to create navigable sections.

Comments are not a courtesy — they are part of the deliverable. Code without comments is incomplete code.

**Never lie in a comment.** A comment that describes what the code used to do, or what a developer intended it to do, rather than what it actually does, is worse than no comment at all. When code is changed, its comments are updated in the same commit. Stale comments that contradict the code are deleted, not left in place.

**Document the journey, not just the destination.** When a working solution was reached after several attempts — which is normal in development, especially AI-assisted development — the final comment must capture:
- What approaches were tried and why they didn't work
- What the working approach is and *why* it works (not just *what* it does)
- Any non-obvious constraint that made earlier attempts fail (an API limitation, a timing issue, a platform quirk)

This is especially critical for regression prevention. If a future developer (or AI assistant) looks at a working solution and doesn't understand why it was written that way, they will "simplify" it and break it. The comment is the defence against that. It should say, explicitly if needed: *"This approach was chosen because [X] — earlier attempts using [Y] failed because [Z]. Do not change this without understanding that constraint."*

### 6.3 No Monolithic Files — Prefer Small, Focused Modules

No Swift file should try to do everything. Each file has one job.

- A view file contains one view (or a tightly related family of sub-views). It does not contain business logic.
- A model file contains one data model. It does not contain UI code.
- A service or manager file handles one concern (e.g., `AnnotationStore.swift` handles annotation persistence; it does not also handle rendering or sync).
- If a file is growing beyond ~200 lines, it is probably doing too many things. Break it up.
- Use Swift's `extension` mechanism to split large types across files by concern (e.g., `Book+Metadata.swift`, `Book+Export.swift`) rather than putting everything in one file.
- Module directories should have a clear, navigable structure. A developer (or an AI coding assistant) should be able to open the project and understand where everything lives within a few minutes.

### 6.4 Advanced Settings — Buried Deep, But There

Apple hides settings that power users need and then calls it "simplicity." Codex does the opposite: the main Settings screen is clean and approachable, but nothing is removed. Every tunable value in the app has a home somewhere in Settings, even if it takes a few taps to find it.

The structure is two-tiered:

**Surface settings** (visible immediately on opening Settings): the things most users will touch — font, font size, margins, line spacing, theme, page turn style, OPDS sources.

**Advanced settings** (behind an "Advanced" row at the bottom of each section, or a dedicated Advanced screen): the things power users need but most users never will — re-ingestion behaviour defaults (what gets cleared on "start from beginning"), annotation misalignment warnings, iCloud resilience options (keep local only, force re-upload), sync granularity, export format defaults, and any other tunable values that emerge during development.

The rule: **if we discussed a tunable value during planning, it gets a setting.** No value is hardcoded without a conscious decision that it should be. When in doubt, make it a setting and put it in Advanced.

This is not an invitation to build a settings screen so complex it needs a manual. Advanced settings should still be well-labelled and explained inline. But they should exist.

### 6.6 Minimize External Dependencies

Every external library added to this project is a liability: a maintenance burden, a potential source of breaking changes on iOS version upgrades, a security surface, and a thing that can disappear from the internet.

**The rule:** Before adding any third-party library or package, the question must be asked — and answered — whether Apple's SDK already provides this capability, or whether a focused custom implementation would be simpler than the dependency it replaces.

Current external dependency status: **none.** This is the goal state. Any decision to introduce a dependency should be recorded here with a justification, so future development sessions start with a clear picture of what was added and why.

If a dependency is added:
- Prefer libraries with no transitive dependencies of their own.
- Prefer libraries that are actively maintained and have a clear Swift Package Manager integration.
- Prefer libraries with permissive open-source licenses (MIT, BSD, Apache 2.0).
- Document the dependency in this section: what it is, why it was added, and what the fallback plan is if it becomes unavailable or unmaintained.

The epub parser evaluation (§9) is the one area most likely to introduce an external dependency. If a parser library is chosen, it is recorded here. If a custom parser is written instead, that decision is also recorded.

---

### 6.5 Work With Apple, Not Against It

iOS and iPadOS have strong, opinionated design patterns. Fighting those patterns to achieve a specific visual effect is almost always a losing battle — it produces fragile code that breaks with OS updates, behaves unexpectedly with accessibility features, and takes far longer to build than the result justifies.

**The rule:** If achieving a desired UI behaviour requires overriding, subclassing, or working around a standard UIKit or SwiftUI component in a non-trivial way, stop and reconsider whether the desired behaviour is worth it.

**Scott will sometimes push for a specific visual detail that requires fighting the framework.** When that happens, it is this project's explicit agreement that the AI assistant will flag it directly:

> *"This approach would require working against how SwiftUI/UIKit handles [X]. Here's what the standard behaviour looks like, and here's what it would take to override it. Given our Occam's Razor rule, I'd recommend accepting the standard behaviour. Want to proceed anyway?"*

This is not a veto — Scott can decide to proceed. But the flag must be raised before any fighting-the-framework code is written. The goal is informed decisions, not silent complexity.

Examples of things that are typically not worth fighting:
- Navigation bar appearance on scroll (accept the system blur/translucency)
- Sheet presentation corner radius and detent behaviour (use the system defaults)
- Font rendering details below 1pt precision (the system knows what looks good on a given screen)
- Keyboard avoidance layout (use SwiftUI's `.ignoresSafeArea(.keyboard)` or the system behaviour; don't roll your own)
- Context menu appearance (use `UIContextMenuConfiguration` or SwiftUI's `.contextMenu` — don't build a custom popover to mimic it)

---

## 7. UX Principles  

1. **The reader is the product.** Every UI decision defers to the reading experience. Navigation chrome disappears when reading. Settings are accessible but not intrusive.
2. **User preference always wins.** The epub file may request specific fonts, font sizes, or layouts. Codex respects these only as defaults. The user can override everything.
3. **Consistency over cleverness.** Page turn style, font, and layout settings never change automatically based on content. What the user set is what they get.
4. **Silent reliability.** Sync happens without user action. Import handles all common cases without error dialogs. The app should never make the user feel like they need to manage it.
5. **No dark patterns.** No permission requests beyond what is strictly needed. No notifications unless the user explicitly enables them. No tracking.

---

## 8. v1 Scope Summary

The following represents the minimum complete product for a first release:

- [ ] epub parsing and rendering with full typography control
- [ ] Book library with grid and list views, cover art display
- [ ] All ingestion paths: Files app, Share Sheet, AirDrop, OPDS, web/Safari import
- [ ] Highlights, notes, and bookmarks with a review screen
- [ ] iCloud sync of reading position and annotations
- [ ] Export annotations as rich text (.rtf), plain text (.txt), or markdown (.md)
- [ ] Send epub to another device or person via AirDrop or system share sheet
- [ ] User settings: font family, font size, margins, line spacing, page turn style, light/dark/sepia themes

---

## 9. Open Questions (to resolve during planning)

- **Epub parser library:** Evaluate FolioReaderKit vs ReadiumSDK vs rolling a custom parser. Decision affects rendering control and maintenance burden.
- **App name:** Finalize before App Store submission. Check trademark availability.
- **Wi-Fi transfer UI:** ✅ **Decided:** Dropped from v1. iCloud Drive already handles epub file sync between devices. Direct device-to-device transfer (MultipeerConnectivity) deferred to v1.1.
- **Epub 3 vs Epub 2 support:** Epub 3 is the modern standard but Epub 2 files are still common. Both should be supported but Epub 3 is the primary render target.

---

## 10. Settings Screen Architecture

Settings references appear throughout every module directive, using paths like "Settings → Reading → Advanced." This section maps the full screen hierarchy so a developer can build the Settings UI without hunting across six directives.

Codex uses the standard iOS `Settings` app-like hierarchy — a root screen with sections, each section drilling into sub-screens. The Settings UI lives inside the app (not in the iOS Settings app), accessible via the options panel in the reader and via the Library's navigation bar.

```
Settings (root)
├── Reading
│   ├── Typography
│   │   ├── Font Family
│   │   ├── Font Size slider (range: see Advanced)
│   │   ├── Line Spacing slider
│   │   ├── Letter Spacing slider
│   │   ├── Text Alignment (Left / Justified)
│   │   ├── Use Book Fonts (toggle)
│   │   └── Margins (Top / Bottom / Left / Right)
│   ├── Theme
│   │   ├── Theme selector (Light / Dark / Sepia)
│   │   ├── Theme mode (Follow System / Always Light / Always Dark / Always Sepia / Scheduled / Match Surroundings)
│   │   ├── Scheduled transitions (time-of-day pickers — shown when mode = Scheduled)
│   │   ├── Match Surroundings threshold (shown when mode = Match Surroundings)
│   │   └── Background Warmth slider
│   ├── Page Turn Style (Curl / Slide / Scroll)
│   ├── Reader Appearance
│   │   ├── Paper Surface (toggle)
│   │   ├── Page Stack Edges (toggle)
│   │   └── Spine and Gutter (toggle)
│   ├── Orientation
│   │   ├── iPad: Auto-switch to Scroll in portrait (toggle)
│   │   ├── iPad: Lock to landscape (toggle)
│   │   └── iPhone: Lock to portrait (toggle)
│   └── Advanced (Reading)
│       ├── Font size minimum (default 8pt)
│       ├── Font size maximum (default 72pt)
│       ├── Publisher mode safety floor (default 10pt)
│       ├── Tap zone layout (left% / centre% / right%)
│       ├── Status bar in reader (Show / Hide)
│       ├── Show time in reader chrome (toggle)
│       ├── Show battery in reader chrome (toggle)
│       ├── Metadata strip display options (toggles per element)
│       ├── Title strip: show book or chapter title
│       ├── Auto-bookmark on scrub (toggle)
│       ├── Reading speed baseline (Auto / manual wpm)
│       ├── Fixed-layout epub handling (Zoom-and-pan / Auto-fit)
│       ├── FOUC protection timeout (default 150ms)
│       ├── Annotation injection timeout (default 100ms)
│       ├── WKWebView memory limit (default 3 chapters)
│       └── Reset all reader settings
│
├── Book Sources (OPDS)
│   ├── [List of configured sources]
│   ├── Add Source
│   └── Set Primary Source (for integrated library search)
│
├── Library
│   ├── Default sort order
│   ├── Default view (Bookshelf / List)
│   └── Advanced (Library)
│       ├── Spine Width
│       ├── Re-ingestion behaviour (bookmarks / highlights / notes on Start from Beginning)
│       ├── "Finished?" threshold (default 90%)
│       ├── "Finished?" idle period (default 7 days)
│       └── Annotation search in library search (toggle — may be slower on large libraries)
│
├── Sync
│   ├── iCloud status (plain-English status indicator)
│   ├── Follow Me / Stay Here switch
│   ├── Time-assisted threshold (shown when Follow Me is on)
│   └── Advanced (Sync)
│       ├── Keep All Books Local (emergency iCloud bypass)
│       ├── Restore All to iCloud
│       ├── Sidecar Files (toggle + write interval)
│       └── Clean up orphaned sidecar files (manual trigger)
│
├── Data & Privacy
│   ├── Export Library Data (generates JSON backup)
│   ├── Import Library Data
│   └── Scheduled Backup (toggle + interval + destination picker)
│
└── About
    ├── Version
    ├── Acknowledgments
    └── Privacy Policy
```

**Implementation note:** The Settings root screen groups items by section with visible headers. Advanced sub-screens are reached via a row at the bottom of each section labelled "Advanced." Advanced screens should have brief inline explanations for each setting — a new user should be able to understand what each setting does without leaving the screen.

---

## 11. First Launch and Onboarding

Codex has no mandatory onboarding flow. There are no tutorial screens, no feature tours, and no signup. The first launch experience is designed to get the user to their books as quickly as possible.

**First launch sequence:**

1. **iCloud prompt** (iOS system prompt, if not already granted): "Codex would like access to iCloud Drive." This is required for the iCloud Drive Inbox and Library folders. If denied, Codex works in local-only mode with a one-time explanation shown on the library empty state.

2. **Empty library screen** (Library Manager §12): a clean screen with a headline, brief explanation of how to add books, and two buttons — Browse Sources and Add a Book. This is the landing page. No splash screen, no walkthrough.

3. **First book added:** when the first book is ingested, no celebration, no confetti, no badge. The book appears on the shelf. Tapping it opens the first-open typography prompt (Rendering Engine §4.6). That prompt is the only "first-time" experience in the reading flow.

**What is deliberately absent:**
- No onboarding carousel or feature tour. The app is simple enough to be self-explanatory.
- No account creation or login. Codex has no accounts — iCloud is the identity layer and it's already set up.
- No push notification permission request on first launch. Codex has no notifications unless a future feature specifically requires them.
- No app review prompt on first launch or early in the session. If one is ever implemented, it fires only after a meaningful reading session (e.g., first book finished), not before.
- No "rate this app" badge, banner, or recurring prompt.

---

*Last updated: April 2026*  
*Project status: Planning phase — all six module directives reviewed and cross-checked. Settings architecture and onboarding added (§10–11). Directive gaps resolved: Highlight Back to Previous reconciled across modules, annotation offset types unified, per-book typography added to sync schema, DRM detection specified, PDF export removed throughout.*
