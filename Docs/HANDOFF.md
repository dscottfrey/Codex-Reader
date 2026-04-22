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

---

## 3. Outstanding work by module

Condensed from the inventory produced on 2026-04-22. Priority order for shipping a usable product: Rendering polish → document picker → CloudKit → Settings screen.

### Module 1 — Rendering Engine

- **Page Curl cross-chapter backward land-on-last-page** — see §2.1.A above.
- **Paginated live-CSS update to neighbour VCs** — see §2.1.B above.
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

- **Custom epub parser, no ReadiumSDK / FolioReaderKit.** Rendering §3.2 spec complete. Implementation lives in `Codex Reader/EpubParser/` (top-level group). See §3.2 of the Rendering directive for the full rationale.

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
