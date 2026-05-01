# Codex Reader — Handoff & Outstanding Work

**Purpose:** what any future session (human or AI) needs to know to pick up where the last one left off — current state, known regressions, TODO inventory by module, and the decisions that shape the architecture.

Last updated: 2026-04-22 (late).

---

## 1. Current build state

- `xcodebuild -scheme "Codex Reader" -destination 'generic/platform=iOS' build` succeeds with zero errors and zero warnings.
- Modules 2–6 have working scaffolding committed (see git log). Module 1 (Rendering) has the custom epub parser and the pagination/page-turn system landed this session; many pieces inside the reader chrome are still TODO (see §3 below).

---

## 2. Known regressions and limitations

These are pieces of behaviour that are either visibly wrong, incomplete, or degraded compared to where we want them. Each is marked with an in-code TODO at the call site so a future session can find it by grep.

### 2.1 Pagination / page turns (Rendering §2.5–§2.7)

**A. Cross-chapter backward lands on page 1, not the last page.**
- **Where:** `Rendering/ReaderView+Surfaces.swift`, `apply(.crossToPrevChapter:)` and `Rendering/ReaderViewModel.swift`, `pendingJumpToLastPage`.
- **Behaviour:** When the reader is on page 1 of chapter B and taps previous, chapter A loads but starts on page 1. The user sees page 1 of chapter A briefly and has to page forward to reach where they visually belong (the end of A).
- **Why:** The new chapter's page count isn't known until its `PaginationJS` has finished measuring (a few frames after load). The UIPageViewController wrapper currently uses a hard-coded `initialPageIndex: 1`.
- **Fix direction:** honour `viewModel.pendingJumpToLastPage` in the coordinator: on the first pagination-report message for the new chapter, if the flag is set, call `coordinator.turnPage` to the last page (or setViewControllers to a page-VC built with the just-measured last index) and clear the flag. Animated `false` so it feels instant.

**B. ~~Live CSS updates only reach the currently-visible page VC.~~ FIXED 2026-04-22.**
- Resolved by the weak-VC registry (`NSHashTable<ChapterPageVC>.weakObjects()`) added to the coordinator. Live CSS updates now iterate all cached page VCs, not just the visible one. Side benefit — the same registry lets JS messages be routed back to the VC whose WebView sent them, which fixed a different bug (see note below).

**C. Paginated chapters only ever display page 1 of the chapter.**
- **Where:** across `Rendering/PaginationJS.swift`, `Rendering/ChapterPageVC.swift`, `Rendering/PaginatedChapterView.swift`.
- **Behaviour:** advance through a chapter — tap by tap, or spread by spread — the animation plays, but each new "page" shows the same content as page 1. Chapter transitions *do* work (chapter 1 advances to chapter 2 correctly), but within each chapter the column never changes. In the two-page spread both sides also show page 1 instead of pages 1 and 2.
- **What's been ruled out:** I already added `!important` via `setProperty` on the column CSS (so the epub's own stylesheet can't override our layout) and wired up a weak VC registry so each VC's pagination message routes back to the correct VC for snapping. Neither was enough.
- **Diagnostic hooks already in place:** `NSLog("[Codex] snapToAssignedPage pageIndex=… webView=…")` in `ChapterPageVC` and `NSLog("[Codex] pagination msg total=… current=… senderPageIndex=… isCurrent=…")` in the coordinator's `didReceive`. Behind `#if DEBUG`. Next session should reproduce the bug on device and paste the `[Codex]` lines from the Xcode console.
- **Hypotheses to investigate (ranked):**
  1. `total=1` in every pagination message → the column layout still isn't applying (epub CSS or shadow DOM quirk). Look at `body.style.cssText` in a JS debug dump.
  2. `total` is correct but `senderPageIndex` for the right-hand VC is always 1 → `makePageVC(pageIndex: N)` is being called with the wrong argument from `turnPage` or `switchToTwoPageSpread`.
  3. `total` is correct, senderPageIndex is correct, but `codexSnapToPage(N)` clamps to 1 in JS → `currentPage = Math.min(n, totalPages)` is running with a stale `totalPages`. Could happen if snap fires before measure completes — add a small `requestAnimationFrame` defer in `codexSnapToPage`.
  4. UIKit keeps reusing the same VC instance for every pageIndex, so our pageIndex parameter never varies in practice. Unlikely but check the `ObjectIdentifier` in the snap log.

**D. Page Curl drag gesture doesn't curl.**
- **Where:** interaction between `Rendering/ReaderView.swift` tap-zone overlays and the underlying `UIPageViewController`.
- **Behaviour:** Tapping the right/left tap zone advances with a proper curl animation (good). Dragging anywhere on the reading surface does nothing — UIPageViewController's built-in drag-to-curl gesture isn't firing.
- **Likely cause:** The transparent `Color.clear` tap-zone views with `.contentShape(Rectangle())` intercept touches at the SwiftUI layer. `.simultaneousGesture(TapGesture())` (which replaced `.onTapGesture`) allows a tap to be recognised alongside underlying gestures, but a touch that moves past the tap-gesture threshold still appears to be consumed by the SwiftUI hit-test without being forwarded to the UIKit-native `UIPageViewController` drag recogniser.
- **Fix direction options:**
  1. Move the tap recognisers off the SwiftUI overlay and attach a `UITapGestureRecognizer` directly to `UIPageViewController.view` via a small helper on the representable. Its delegate's `shouldRecognizeSimultaneouslyWith` returns `true` so the built-in drag-to-curl continues to work.
  2. Replace tap zones with a single `DragGesture(minimumDistance: 0)` on the reading surface and classify by translation — short movement = tap, longer = forward to UIKit. Messier.
  3. Accept the trade-off and hide the drag-to-curl affordance entirely (taps only). Not recommended — drag is part of the Apple Books paradigm users expect.

**E. Scrolling stops working after switching from Page Curl (via rotation or style change).**
- **Where:** interaction between `Rendering/ReaderView+Surfaces.swift`'s surface dispatch (`paginatedSurface` vs `scrollSurface`) and leftover state from the previous surface.
- **Behaviour:** Selecting Scroll in settings directly: scroll works. Selecting Page Curl, then rotating (or otherwise transitioning to a state where Scroll should be active): vertical scroll no longer responds.
- **Unknown / open:** it's not clear yet whether the issue is (i) the expected orientation auto-switch to Scroll (§2.6) simply isn't implemented, so the user is still in Curl after rotation, OR (ii) the WKWebView from the previous `paginatedSurface` isn't being cleanly torn down when SwiftUI swaps to `scrollSurface`, leaving stale hit-test state.
- **Fix direction:** implement §2.6 orientation auto-switch first (if the user expected rotation to switch modes automatically, delivering that will remove the ambiguity). Then verify clean teardown of the paginated surface when `paginatedMode` flips — the `.id()` trick currently depends on the chapter URL + transition style; may also need to include `paginatedMode` or force the surface to unload.

**F. Drag-to-curl past a cross-chapter right page does not advance.** **HIGH PRIORITY.**
- **Where:** `Rendering/PaginatedChapterView.swift`, the `viewControllerAfter` and `viewControllerBefore` data source methods. Also relevant: the `swapInCrossChapterRightPageIfNeeded` helper added 2026-04-29.
- **Behaviour:** On iPad landscape Page Curl, when the open-book spread shows the last page of chapter A on the left and the first page of chapter B on the right (the cross-chapter spread filler), dragging right does nothing. Tapping the right tap-zone DOES advance — that path goes through `handleNextPageTap` → `PageNavigator` → `swapChapter`, which doesn't touch the data source.
- **Why:** The data source's `viewControllerAfter` checks `vc.pageIndex < totalPages`, where `totalPages` is the *current* chapter's page count. When the right-side VC is already a chapter B page (cross-chapter spillover), asking for "the page after it" still uses chapter A's totalPages — so the check fails and `nil` is returned. UIPageViewController disables the swipe gesture in that direction.
- **Fix direction:** Extend the coordinator to know about the spine, not just the current chapter. `viewControllerAfter` should detect "this VC is for a different chapter than my currentChapterURL" and return the next page of THAT chapter (or page 1 of the chapter after it). This requires plumbing the parsed spine into the coordinator and giving each `ChapterPageVC` a way to identify "which chapter am I in." When the user successfully swipes into the next chapter, the coordinator must also notify the view model so `currentChapterHref` flips before the next surface rebuild — otherwise reading position state becomes inconsistent. This is a larger architectural change than the cross-chapter render itself: the coordinator currently believes it owns exactly one chapter, and the SwiftUI surface rebuilds on every chapter change. The cleanest path is probably to have `PaginatedChapterView` span the whole book rather than per-chapter, but that's a refactor — preserve the per-chapter rebuild as the cheaper option if it can be made to work.
- **Why high priority:** Drag-to-curl is the primary navigation gesture on iPad and the directive's expected feel (Apple Books parity per memory `project_page_curl_deal_breaker`). Tap-only navigation across chapter boundaries is a noticeable regression from the rest of the app.

---

## 3. Outstanding work by module

Condensed from the inventory produced on 2026-04-22. Priority order for shipping a usable product: Rendering polish → document picker → CloudKit → Settings screen.

### Module 1 — Rendering Engine

- **HIGH PRIORITY: Drag-to-curl across chapter boundary** — see §2.1.F above. Tap navigation works; swipe/drag does not. Architectural change to the coordinator data source.
- **Page Curl cross-chapter backward land-on-last-page** — see §2.1.A above.
- **Paginated live-CSS update to neighbour VCs** — see §2.1.B above.
- **Review unused `pagesRemainingInBook`** (`Rendering/PaginationEngine.swift`). Computed and exposed but no UI consumer after the metadata strip switched to `pagesRemainingInChapter`. Kept on the assumption it'll feed the progress scrubber or the "Finished?" prompt; drop if no consumer materialises.
- **Per-page metadata layout for the iPad-landscape spread.** Right now the metadata strip is one centered line at the bottom of the viewport, so it reports the LEFT page only — always an odd number in spread mode (1, 3, 5…). It's correct but reads as "where did the even pages go?" Proposed redesign: page number centered at the bottom of each column individually (so the spread shows e.g. "47" under the left column and "48" under the right), with the total-pages and "X left in chapter" relegated to the gutter between columns (Codex's existing column-gap area). Open design question first: Apple Books treats each two-page spread as ONE page in its numbering — there is probably a rationale for that (chapter-length math is cleaner; user mental model matches a printed book where "open the book to page 12" means the spread, not just the left side). Investigate that decision before committing to the per-column-number approach. The metadata strip lives in `Rendering/ReaderChromeView.swift` (`metadataStrip`) and is positioned as a single bottom-centered Text — splitting it across columns will need either a column-aware overlay positioned in screen coordinates relative to the spread, or the numbers being injected into the WKWebView body itself (CSS `::after` on the column container, or a JS-injected element per column). Both have tradeoffs worth weighing before code lands.
- **Default margins (left / right / center) and text justification.** Current shipped defaults in `Models/ReaderSettings.swift` are 20pt on each side and `.left` alignment, with a "center margin" (the spread gutter) derived implicitly in `PaginationJS.applyLayout` as `padLeft + padRight`. These were placeholder values picked early and need a deliberate pass: pick visually correct defaults for iPad landscape spread, iPad portrait single, and iPhone single; consider exposing the gutter as its own setting rather than computing it from L+R; revisit whether `.justified` should be the default for prose books (most printed books are justified, current `.left` matches Apple Books but leaves a ragged right edge that some readers find less booklike). Tied to the directive's §10 Settings Architecture work — these decisions feed into the surface settings shown to first-time users and the Advanced floor/ceiling values.
- **Speculative pre-render of the next spread.** Goal: as soon as the current spread finishes rendering, start rendering the next spread (or the first spread of the next chapter) in the background, so a forward tap or swipe always feels instant. Within a single chapter UIPageViewController already pre-builds neighbouring page VCs (~3 alive at once per `ChapterPageVC.swift` memory note), so within-chapter advance is mostly fine. The gap is at chapter boundaries: today, crossing into chapter B via `swapChapter` rebuilds the whole `PaginatedChapterView`, which loads chapter B's file, parses it through PaginationJS, runs the measure pass, and injects CSS — all on the critical path of the user's tap. A cold cross-chapter advance is visibly slower than a within-chapter one. Proposed approach: keep one chapter ahead pre-rendered. Pairs naturally with the §2.1.F spine-aware coordinator refactor — once the data source can build cross-chapter VCs, UIKit's existing pre-fetch behaviour will warm them automatically. Discard the pre-render on: setting changes (CSS regen invalidates the prepared page), font/typography changes, rotation, and any TOC/scrubber jump that doesn't land on the pre-rendered chapter. Memory budget should stay near the existing ~3 live WebViews — the pre-render replaces, not adds to, the working set. Worth measuring the cold-vs-warm cross-chapter latency before building, to decide whether the perceived win justifies the bookkeeping.
- **Bookmark ribbon wiring** (`Rendering/ReaderView.swift:~55–60`). Ribbon is visible but `isBookmarked: false` is hard-coded; `onTap` / `onLongPress` are empty.
- **Options panel** (§4.1 Chrome System 2) — no invocation mechanism, no panel view. TOC, progress scrubber, share, bookmarks-review, book details, full-screen toggle all unreachable.
- **Metadata strip assembly from Advanced Settings toggles** (§4.5). Currently a placeholder string.
- **Orientation auto-switch to Scroll on iPad portrait** (§2.6) — not implemented.
- **Match Surroundings ambient-brightness theme mode** (§2.10) — not implemented.
- **Background Warmth slider** (§2.10) — not implemented.
- **Skeuomorphic surfaces** — Paper Surface, Page Stack Edges, Spine/Gutter (§2.9). None implemented.
- **Font list from `UIFont.familyNames`** (`ReaderSettingsPanel.swift:~109`). Currently a minimal hardcoded list.
- **Settings persistence to `ReaderSettingsRecord`** (`ReaderSettingsPanel.swift:~151`) — TODO.
- **First-open typography prompt preview content** (`TypographyPromptView.swift`) — shell only. Side-by-side preview, excerpt lookup (landmarks/guide/heuristic), customise path all need filling in.
- **iCloud URL resolution** (`ReaderViewModel.swift`, `currentEpubURL()`) — treats iCloud paths as local paths.
- **Find in book** (§8) — not implemented.

### Module 2 — Ingestion Engine

- **iCloud container identifier** — no iCloud container configured at the app level; everything writes to Application Support as fallback. Blocks Sync Engine.
- **Duplicate prompt UI** (resume / start-over / add-as-new). Pipeline throws `.duplicateDetected`; no UI shows it.
- **Document picker, share-sheet intake, URL handling** — not wired into the app.

### Module 3 — Library Manager

- **"Read Next" shelf** (`BookshelfView.swift`) — returns empty; Collection lookup not wired.
- **CoverFlow browser** — "Show All" buttons do nothing.
- **Sources tab** (`EmptyLibraryView.swift`) — OPDS client exists; no UI navigates to it.
- **Document picker entry** (`EmptyLibraryView.swift`) — "Add a book" button empty.
- **Book Detail actions** (`BookDetailView.swift`) — File…, Force Re-upload, Reset Progress all TODO.
- **Search** — no search field, no results UI.
- **First-launch onboarding source** — not hooked to UserDefaults.

### Module 4 — Sync Engine

- **CloudKit activation** — SwiftData container has `isStoredInMemoryOnly: false` but no CloudKit container identifier in entitlements. No cross-device sync yet.
- **Sidecar annotation schema** (`SidecarWriter.swift`) — Annotation not fully reflected.
- **Portable export/import UI** — engine exists; no user-facing button.
- **"Finished?" prompt UI** — detection logic exists; no SwiftUI sheet.

### Module 5 — Share & Transfer

- **Highlight text in annotation export** (`AnnotationExporter.swift`) — uses a placeholder for the highlighted passage; straightforward to finish now that the parser is real.
- **Share button in Annotation Review** — export runs; result isn't handed to a share sheet.

### Module 6 — Annotation System

- **Highlight creation from text selection** — `UIEditMenuInteraction` callout extension (§4.8) not wired. No path from a reader text selection to `AnnotationStore.create`.
- **Bookmark creation/toggle from the ribbon** — see Module 1.
- **Annotation review filter tabs** — `AnnotationReviewView.swift` is a shell; filter logic likely incomplete.

### App-level (Overall Directive §10, §11)

- **Settings screen architecture** (§10) — no `Settings/` folder. Every Advanced Setting in Rendering §4.5 has no UI. `ReaderSettingsRecord` persists but the user can't change anything outside the in-reader Aa panel.
- **Onboarding** (§11) — no first-launch flow.
- **App icon / launch screen** — likely defaults.

---

## 4. Architectural decisions worth remembering

- **~~Custom epub parser, no ReadiumSDK / FolioReaderKit.~~ SUPERSEDED 2026-05-01.** The reader now uses Readium Swift Toolkit (pinned at 3.8.0); the custom parser at `Codex Reader/EpubParser/` is retained for ingestion-time metadata/cover extraction only. See "Reader uses Readium…" below and Rendering §3.2.

- **Reader uses Readium Swift Toolkit; ingestion still uses the custom epub parser.** Rendering §3.2. The reader's load path lives in `Codex Reader/EpubLoader/EpubLoader.swift` and wraps Readium's `AssetRetriever` / `PublicationOpener` / `GCDHTTPServer` to serve chapter resources to WKWebView via localhost URLs. Ingestion (`IngestionPipeline` + `CoverExtractor`) stays on the custom parser at `Codex Reader/EpubParser/` for now — see "Ingestion still on the custom epub parser" below for the migration plan.

- **Readium pinned at 3.8.0** (March 2026). SPM products imported: `ReadiumShared`, `ReadiumStreamer`, `ReadiumAdapterGCDWebServer`. `ReadiumNavigator` is *not* used — Codex implements its own rendering pipeline (CSS Columns + WKWebView snapshot pipeline per Rendering §3.3+).

- **Readium GCDHTTPServer is deprecated — plan migration to a custom URL scheme handler.** `GCDHTTPServer` is marked `@available(*, deprecated, message: "The Readium navigators do not need an HTTP server anymore. This adapter will be removed in a future version of the toolkit.")` in Readium 3.8. Readium's own navigators have moved to a `WKURLSchemeHandler` against a `readium://` scheme — Readium does not export that handler as public API. We're using the deprecated server anyway because it drops localhost URLs into existing `WKWebView.load(URLRequest:)` calls unchanged (~5 LOC of integration); the alternative is ~50–80 LOC of custom URL-scheme-handler bridging that doesn't earn its keep for a proof-of-concept. Migration is contained in `EpubLoader.swift` plus the WKWebView config — `ParsedEpub.SpineItem.absoluteURL` stays a `URL`, just with a different scheme. Trigger to revisit: a Readium release announces removal of `GCDHTTPServer`, OR we hit a real transport limitation (CORS, mixed-content warnings, App Transport Security, service worker quirks).

- **Ingestion still on the custom epub parser — narrower scope for the Readium experiment.** Only the *reader* moved to Readium. `IngestionPipeline` continues to call `EpubParser.parse(_:)` for metadata + cover extraction at ingest time. Reason for holding off: the experiment branch validates that Readium can render chapters into the existing WKWebView/CSS-Columns/page-curl pipeline; migrating ingestion adds work without buying validation signal. Trigger to revisit: the first epub that ingests poorly with the custom parser, or the first malformed-epub display issue traceable to parser limitations. Migration shape: replace `EpubParser.parse(sourceURL)` with an `EpubLoader.extractMetadata(_:)` call that reads metadata + cover bytes via `Publication.get(coverHref).read()` — no HTTP server needed at ingest time. After migration the entire `Codex Reader/EpubParser/` source group is deleted.

- **ZIP extraction uses Foundation's `Compression` framework, not `Process()/unzip`.** The directive's literal code is macOS-only (`Process` is unavailable on iOS). The custom ZIP reader (`EpubParser/ZipReader.swift`) honours the directive's intent — "no third-party dep, use what's on the system" — with an iOS-compatible implementation. The deviation is documented in `EpubArchive.swift`'s file header.

- **Page Curl and Slide share a `UIPageViewController` wrapper** (`PaginatedChapterView.swift`) per Rendering §2.5. Each page is its own `ChapterPageVC` with its own WKWebView locked to one column. UIPageViewController keeps ~3 page VCs alive (current/prev/next), which matches the §5 memory budget. **No third-party libraries.**

- **Scroll mode stays on plain `WKWebViewWrapper`** — native vertical scroll, progress reported via the same JS bridge.

- **Debounced position save** (`ReaderViewModel.savePositionDebounced`) — ~800ms window, coalesces back-to-back updates so SwiftData isn't thrashed during a rapid swipe. On `ReaderView.onDisappear` we flush pending saves.

- **PaginationJS `codexSnapToPage` vs `codexGoToPage`** — snap is silent (used by page-VC initial lock); go posts a `pageChanged` message (used for user-initiated jumps, scrubber, TOC). Keeps the view model from seeing spurious page-change events during setup.

- **Message-handler filtering** — the paginated coordinator filters incoming pagination messages to only the currently-visible page VC's `WKWebView`, so neighbour VCs don't emit events that confuse the engine.

---

## 5. How to read this document

- **Priority ordering in §3** is the suggested build order, not a contract. Happy to reorder.
- **Anything with a file:line reference** in this doc should have a matching `// TODO` or file-header note in-code; when you finish an item, delete the in-code TODO and move the line here to a "Done" section (or delete it from here).
- **Keep the Known Regressions section in §2 tight.** Items leave that section when they're fixed or when they become general TODO entries in §3.
