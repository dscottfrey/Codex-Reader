# Codex — Module 3: Library Manager Directive

**Module:** Library Manager  
**Priority:** High — the primary non-reading UI of the app  
**Dependencies:** Ingestion Engine (populates library, iCloud states), Sync Engine (reading state, recently active stack, "Finished?" logic), Rendering Engine (launched from library), Annotation System (annotation counts displayed per book)

---

## 1. Purpose

The Library Manager is the home screen of Codex and the primary non-reading interface. It presents the user's book collection, provides access to OPDS book sources, and surfaces the reading state of every book in the library — including iCloud sync status, progress, and completion state.

The library should feel like a personal bookshelf — calm, organised, and immediately useful. It should not feel like a store, a dashboard, or a productivity app.

---

## 2. Top-Level Structure

The library has two distinct areas, accessible via tabs or a sidebar:

**Local Library** — books stored in `iCloud Drive/Codex/Library/`. This is the user's shelf. The vast majority of time is spent here.

**Sources** — OPDS-connected book servers (COPS, Calibre-Web, Standard Ebooks, etc.). This is where the user browses and downloads new books. See §9 for the full Sources UI spec.

On iPhone: tabs at the bottom of the screen (Library | Sources).  
On iPad: a sidebar with Library and Sources as top-level items, collections and filters nested beneath Library.

---

## 3. The Two Views

The library offers two views, toggled by a button in the navigation bar. The preference persists across launches.

- **Bookshelf View** — the primary, skeuomorphic view. Books arranged on wooden shelves, cover-out at centre fading to spine-out at edges. Described in full in §4.
- **List View** — a plain, information-dense list. Described in §5.

---

## 4. Bookshelf View

### 4.1 Philosophy

The Bookshelf view is the heart of Codex's visual identity. It uses deliberate, earned skeuomorphism — a wooden bookshelf is one of the few UI metaphors that genuinely maps to the content it represents. The goal is warmth and familiarity, not novelty. It should feel like walking up to your own bookcase.

### 4.2 Shelf Structure

The library is presented as a vertical stack of named shelves. Each shelf is one row, rendered as a wooden surface with books sitting on it. The shelves scroll vertically; the books on each shelf scroll horizontally.

**Shelf order (top to bottom):**

| Shelf | Name | Contents | Curation |
|---|---|---|---|
| 1 | Now Reading | Books from the recently active stack (Sync Engine §7.1) | Auto |
| 2 | Up Next | "Next in Series" (auto) + books tagged "Read Next" (manual) | Mixed |
| 3+ | User Collections | Each named collection is its own shelf | Manual |
| Last | Everything Else | Books not in any collection and not on shelves 1–2 | Auto |

**Shelf 1 overflow into Shelf 2:** If "Now Reading" has fewer books than fit the shelf width, the shelf continues seamlessly into "Up Next" books — no visual break, no label change mid-shelf. The "Up Next" label only appears as its own shelf when "Now Reading" is full enough to push it to a second row.

**"Next in Series" logic:** If the user is reading book N in a series and has book N+1 in their library, book N+1 appears automatically on the Up Next shelf. If they have N+1 but not N+2, only N+1 appears. The series number field in the book's metadata (editable in Book Details) drives this.

**"Read Next" tag:** Applied manually via context menu → "Add to Up Next". Appears on the Up Next shelf alongside auto-curated series books. Both sources are visually identical on the shelf — curation method is not exposed in the UI.

### 4.3 The Cover-to-Spine Transition

This is the defining visual feature of the Bookshelf view. Books are displayed using a `ScrollView` + `scrollTransition` in SwiftUI, which drives a continuous cover-to-spine transition as books move from the centre of a shelf toward the edges.

**At centre:** the book is fully cover-out — the complete cover image is visible, facing the reader. One or two books may be fully cover-out simultaneously, depending on screen width.

**Toward the edges:** as a book scrolls away from centre, `rotation3DEffect` around the Y axis rotates it progressively toward spine-out. Simultaneously, `opacity` decreases. By the time a book reaches the shelf edge it is nearly edge-on and fading — implying more books beyond.

**The face swap:** a book cell has two rendering modes — cover mode and spine mode. When the `scrollTransition` phase exceeds a threshold (~70° of rotation), the cell switches from rendering the cover image to rendering the spine view. This prevents the cover image from appearing as a distorted sliver at high rotation angles.

**Implementation note:** This is the most visually complex component in the app. It is achievable entirely within standard SwiftUI (`scrollTransition`, `rotation3DEffect`, `opacity`). No private APIs, no third-party libraries, no framework fighting. It is non-trivial to tune well — the rotation curve, the face-swap timing, and the fade rate will require visual iteration during development.

### 4.4 Spine Rendering

When a book is in spine mode, it renders as a narrow vertical rectangle:

**Spine background colour:** extracted from the book's cover image at ingestion time using `UIImage` colour analysis (dominant colour). Stored in the book's metadata. This gives each spine its own identity, just like a real bookshelf.

**Text contrast:** the spine text colour (dark or light) is calculated from the spine background colour's luminance. Target minimum contrast: WCAG 4.5:1. For borderline colours (mid-luminance, highly saturated), a semi-transparent text background strip may be applied to guarantee legibility.

**Spine text:** title and author, rendered vertically (rotated 90° — text reads bottom to top, as is conventional for books in English). Both title and author are shown. If truncation is necessary due to book height constraints, title takes priority.

**Spine width:** uniform across all books on all shelves. Width = spine font size + generous padding (exact value tuned during development, targeting comfortable legibility at reading distance). Configurable in Advanced Settings → Library → Spine Width.

**State indicators on spines:** when a book has an iCloud state issue (§6), a small indicator badge appears at the bottom of the spine rather than overlaid on the cover. Ghost records (missing files) render with a desaturated spine and a faint broken-link icon.

### 4.5 Shelf Aesthetics

**The shelf surface:** a wooden texture rendered beneath the books. The aesthetic target is warm and natural, not cartoon-like. Two options to decide during visual design:
- **Textured / photorealistic:** a wood grain texture image tiled beneath the books. More immersive. Requires sourcing a high-quality, licence-free texture.
- **Flat / modern-skeuomorphic:** wood-toned colour with a subtle shadow beneath the books and a thin highlight along the top edge of the shelf. No texture image. Easier to implement, scales cleanly to all screen sizes and dark mode.

This is a visual design decision to be made during the early build phase. Both are implementable without framework fighting. The flat/modern approach is Occam's Razor; the textured approach is more ambitious but only marginally more complex.

**Shelf labels:** each shelf has a small label above it (e.g., "Now Reading", "Up Next", "Science Fiction"). Tapping the label opens the shelf in the full-screen CoverFlow browser (§4.6).

**Progress bars:** shown only on the face-out (centre) book, and only when a long press is active. Not shown passively, not shown on spine-out books.

### 4.6 "Browse Shelf" — CoverFlow Mode

Tapping a shelf label, or tapping a "See all →" count badge at the right edge of a shelf, opens a full-screen **CoverFlow browser** for that collection.

CoverFlow mode displays all books in the collection as a horizontally scrollable `ScrollView` with `scrollTransition` driving the same cover/spine transition as the main shelf — but full-screen, with larger covers and more visual breathing room. This is where the CoverFlow effect is most useful: browsing a large collection (a full series, a reference section, all 300 science fiction books) where you want visual richness and fast scanning.

Tapping a book in CoverFlow opens it. Long-pressing reveals the context menu. A back button or swipe-down dismisses CoverFlow and returns to the main bookshelf.

---

## 5. List View  

A clean, information-dense alternative for users who prefer text over visuals, or who are managing a large library efficiently.

Each row shows:
- Cover thumbnail (small, left-aligned)
- Title (primary text)
- Author (secondary text)
- Series name and number (tertiary, if applicable)
- Reading progress (percentage, or "Finished")
- Last read date (small, trailing)
- State indicator icon (far right, if applicable — see §6)

Swipe left: **Delete**, **Share**  
Swipe right: **Mark as Finished**, **Keep on Device**  
Tapping a row opens the book.

List view uses the same filter tabs and sort options as the bookshelf view. It does not have the shelf metaphor — books are presented as a flat sorted list.

---

## 6. Tap and Long Press Behaviour

### 6.1 The Fundamental Rule

**A single tap on any book — face-out or spine-out, on the bookshelf or in CoverFlow — always opens the book.** No exceptions. There is no ambiguity about what a tap does.

All other interactions are behind a long press.

### 6.2 Long Press on a Face-Out (Centre) Book

Long-pressing the fully face-out book in the bookshelf view, or the centre book in CoverFlow, reveals a rich overlay on the cover showing:

- Reading progress bar
- Sync/iCloud state (plain English: "Stored in iCloud" / "Not downloaded" / "Upload stuck" / "File missing")
- **"Finished?"** button — only shown if the book meets the completion criteria (progress > 90%, not opened in > 7 days, not already finished — thresholds in Advanced Settings)
- The full context menu (§9)

The overlay appears on the cover itself — the book stays in place, doesn't pop or scale up. The context menu appears below or above the cover depending on vertical position on screen (standard iOS context menu behaviour).

**"Finished?" from the overlay** opens the completion panel defined in Sync Engine §13.3 — three independent toggles (remember end point, remove from shelf, remind me next time) and a Confirm button.

This is the only place in the bookshelf view where Codex surfaces completion or sync state. The shelves remain visually clean during normal browsing.

### 6.3 Long Press on a Spine-Out Book

Long-pressing a spine-out book shows an **abbreviated context menu** — only the actions that make sense without needing to see or interact with the full book detail:

- Open
- Add to Collection
- Share
- Mark as Finished / Mark as Unread
- Delete

No sync state, no Finished? button, no file management options. Those are accessible by navigating to the book's detail view (via context menu → Book Details, available from the face-out long press).

### 6.4 Ghost Records in the Bookshelf

Books with missing files (ghost records) appear on the shelf with a visually distinct spine — desaturated, slightly translucent. In the Unavailable filter view, ghost records are shown face-out with a greyed cover. A single tap on a ghost record does not open the reader (there is no file to open) — instead it opens the Book Detail view directly, where the re-import and recovery options are available. This is the one exception to the "tap always opens" rule, and it is unavoidable.

### 6.5 State Indicators in List View

The List view is information-dense by nature and can carry persistent state indicators without cluttering artwork. Each row shows a small icon at the right edge for any non-normal iCloud state:

| State | Icon | Meaning |
|---|---|---|
| Uploading | ↑ | Upload in progress |
| Upload stuck | ⚠️ | Upload stalled — long press for options |
| Cloud-only | ☁️ | Not downloaded locally |
| Downloading | ↓ | Download in progress |
| Download stuck | ⚠️ | Download stalled — long press for options |
| Local only | 📱 | iCloud bypassed for this book |
| File missing | 🔗 | Ghost record — tap to view details |
| Normal | — | Nothing shown |

Tapping a row still opens the book (or Book Detail for ghosts). Long press shows the full context menu including sync state explanation and recovery options.

---

## 7. Ghost Records — Books Without Files

When a book's epub file is missing from iCloud Drive (deleted externally, permanently evicted, or iCloud Drive having a bad day) but the SwiftData record still exists, the book is a **ghost record**. Codex does not delete ghost records automatically — the metadata, reading position, and annotations are preserved.

Ghost books appear in the library with a greyed-out cover and a broken-link indicator (§5). They are fully browsable — the user can see their annotations, progress, and history — but cannot be opened for reading until a file is available.

Actions available on a ghost record (context menu):
- **Re-import** — opens the document picker or OPDS source browser to find and re-ingest the book. Codex matches by title + author and restores the existing record.
- **View Annotations** — opens the annotation review screen even without the file
- **Export Annotations** — export highlights and notes to rich text, plain text, or markdown
- **Remove** — permanently deletes the record and any sidecar file

Ghost records are included in a **filter tab**: Library → Unavailable. They do not appear by default in the main All / Reading / Unread / Finished views, so they don't clutter the main shelf.

---

## 8. Navigation & Organisation

### 8.1 Filter Tabs

At the top of the Local Library: **All | Reading | Unread | Finished | Unavailable**

- **All** — all books with local files (ghosts excluded)
- **Reading** — progress > 0% and not finished
- **Unread** — progress = 0%
- **Finished** — marked as finished
- **Unavailable** — ghost records only

### 8.2 Sorting

Sortable by: Title (A–Z / Z–A), Author (A–Z / Z–A), Date added (newest / oldest), Last read (most recent first), Reading progress (unread first / finished first).  
Sort preference persists across launches.

### 8.3 Collections (Shelves)

User-created named collections, like playlists. A book can belong to multiple collections. Collections appear in the sidebar (iPad) or a secondary screen (iPhone), below the smart filter tabs.

Smart collections (auto-populated, not editable): All Books, Reading, Unread, Finished.  
Manual collections: user-created, books added explicitly via context menu → Add to Collection.

**v1 note:** If custom collections add significant complexity to the initial build, ship with smart filter tabs only and add manual collections in v1.1. The architecture should accommodate them from the start even if the UI ships later.

### 8.4 Search

#### Invoking Search

Two equivalent ways to open search:
- Tap the magnifying glass icon in the navigation bar
- Pull down on the bookshelf surface (like iOS Spotlight)

Both reveal the search bar at the top of the screen. The **top shelf transitions to a "Results" shelf**, replacing "Now Reading" for the duration of the search. The remaining shelves stay visible and scrollable below, giving context. Dismissing search (tap Cancel, swipe the bar upward, or clear the query) restores "Now Reading" with a smooth transition.

#### What Is Searched

Search runs two concurrent queries and merges results into the single Results shelf:

**Local library** — title, author, series name, and optionally annotation text (Advanced Settings toggle — annotation search may be slower on large libraries). Local results appear immediately. Ghost records are included so the user can find and re-import a missing book by title.

**Primary OPDS source** — the user's designated primary book server (set in Settings → Book Sources → Set as Primary). Queried simultaneously with the local search. Results arrive slightly later as the network responds, populated into the Results shelf progressively. A subtle loading indicator on the Results shelf label ("Results ↻") shows while the OPDS query is in flight. When complete it resolves to "Results (N local, N from [Source Name])".

Only the primary OPDS source is searched automatically. Other configured sources are accessible via the Sources tab.

#### Visual Treatment in Results

Local books appear with their normal spine/cover rendering. Remote books (from OPDS, not yet in the local library) are visually identical except for a small **cloud/download badge** on the spine or cover face — enough to distinguish them without breaking the visual rhythm of the shelf.

#### Tapping Results

**Local book:** tap opens it immediately. Same as tapping anywhere else.

**Remote book:** tap begins downloading silently in the background. The cloud badge immediately transforms into a **circular progress indicator** showing download progress. No dialog, no confirmation. The user can:

- **Stay on the Results shelf** — when the download completes, the book opens automatically, exactly as if it had been a local book tapped in the first place. The circular progress fills, then the book opens.
- **Navigate away** — the download continues in the background. The book appears in the local library when complete, the circular progress visible on its spine in whatever view is showing. No auto-open.

The circular progress indicator on remote books behaves identically to the iCloud downloading indicator on evicted books — same component, same visual language.

#### Long Press on Results

**Local book:** Add to Up Next / More Info (Book Detail sheet).

**Remote book:** Add to Up Next (queues download if not already downloading, then tags the book as "Read Next" once it lands in the library) / More Info (shows OPDS metadata — title, author, description, series — in a lightweight preview sheet, with a Download button).

---

## 9. Bulk Select

### 9.1 Entering Selection Mode

An **Edit** button in the navigation bar enters bulk selection mode.

- **In list view:** checkboxes appear on the left of each row. Tapping a row selects or deselects it. The book no longer opens on tap while in selection mode.
- **In bookshelf view:** tapping Edit automatically switches to list view first, then enters selection mode. Bulk operations belong in the list — the bookshelf is a browsing and reading interface, not a management one. This is by design.

A **Select All** button appears in the navigation bar once selection mode is active. The nav bar also shows a running count: "3 Selected."

Tapping **Cancel** exits selection mode and returns to the previous state (including returning to bookshelf view if that's where the user came from).

### 9.2 Bulk Action Bar

Once at least one book is selected, an action bar appears at the bottom of the screen with the available bulk actions. Actions that don't apply to the current selection are greyed out (e.g., "Remove Local Copy" is greyed if all selected books are already cloud-only).

| Action | Behaviour |
|---|---|
| **Delete** | Confirmation: "Delete [N] books? Their epub files and sidecars will be removed. Annotations remain in your library export." [Delete] [Cancel] |
| **Add to Shelf** | Opens a shelf/tag picker. Selected books are added to the chosen shelf(ves). A book can be added to multiple shelves. |
| **Add to Up Next** | Tags all selected books as Read Next. They appear on the Up Next shelf. |
| **Mark as Finished** | Marks all selected books as finished. |
| **Mark as Unread** | Resets reading progress to 0% on all selected books. Requires confirmation if any selected books have annotations. |
| **Keep on Device** | Pins local copies, prevents iCloud eviction, for all selected books. |
| **Remove Local Copy** | Allows iCloud to evict local copies of all selected books (keeps records and metadata). |

### 9.3 Tags and Shelves — Same Thing

A note on terminology: **tags** and **shelves** refer to the same underlying concept (a Collection in the data model). Tagging a book "Hiking" adds it to the Hiking collection, which appears as the Hiking shelf in the bookshelf view. The UI uses "shelf" when in a spatial/visual context (bookshelf view) and "tag" when in a management context (bulk operations, Book Detail). Both words mean the same thing and both are acceptable — the important thing is consistency within each context.

---

## 10. Context Menu (Long Press)

| Action | Notes |
|---|---|
| **Open** | Opens at last reading position |
| **Book Details** | Opens detail/edit sheet (§10) |
| **Share** | Send epub via AirDrop / share sheet |
| **Export Annotations** | Export to rich text (.rtf), plain text (.txt), or markdown (.md) |
| **Add to Collection** | Add to one or more user collections |
| **Keep on Device** | Pin epub locally, prevent iCloud eviction |
| **Remove Local Copy** | Allow iCloud to evict the local file (keep record) |
| **Force Re-upload** | Restart a stuck iCloud upload |
| **Replace File…** | Import a fresh epub to replace a broken/missing file |
| **Mark as Finished** | Manually mark finished |
| **Mark as Unread** | Reset progress to 0% (with confirmation) |
| **Delete** | Remove epub, sidecar, and SwiftData record (with confirmation) |

Not all actions are shown for all books. Actions are contextually filtered based on the book's current state — a cloud-only book does not show "Remove Local Copy"; a ghost record does not show "Keep on Device."

---

## 11. Book Detail View

Accessible via context menu → Book Details, or by tapping a book card and choosing Details.

Presented as a sheet with two sections: **Info** (read and edit) and **File & Sync** (status and controls).

**Info section:**
- Cover image — tappable to replace (opens photo picker or document picker for an image file)
- Title — editable
- Author — editable
- Series — editable (name and number, e.g. "Dune, 1")
- Language
- Publisher
- Epub version (2 or 3)
- Word count estimate
- Date added
- Last read date and device

**File & Sync section:**
- iCloud file state (plain English: "Stored in iCloud Drive", "Downloading…", "Not downloaded", "File missing")
- File size
- Storage location (iCloud Drive or Local Only)
- **Keep on Device** toggle
- **Force Re-upload** button (shown if stuck)
- **Replace File…** button (always available)
- Sidecar file status (last written timestamp) — shown only if sidecars are enabled in Advanced Settings

**Reading History section:**
- Reading progress (%)
- Custom end point (if set via "Finished?" toggle — shows "Book considered finished at X%")
- "Did not finish" flag — if set, shows date and a button to clear it
- **Reset Progress** button (clears reading position only, with confirmation)

**Open Book** button at the bottom.

---

## 12. Empty State

When the library has no books, a clean, friendly screen with:
- A simple illustration (no emoji, no cartoon — something understated)
- Headline: "Your library is empty"
- Body: "Add books from your Calibre server, iCloud Drive, AirDrop, or the Files app."
- **Browse Sources** button — takes the user to the Sources tab
- **Add a Book** button — opens the document picker

This is frequently the first screen a new user sees. It should be calm and instructive, not alarming.

---

## 13. Sources Tab — OPDS Browser

The Sources tab lists all configured OPDS book servers. Each source is a tappable row showing the source name and URL.

**Managing sources:**  
Settings → Book Sources → Add / Edit / Delete. Each source has a name, OPDS feed URL, and optional credentials (stored in iOS Keychain).

Pre-configured defaults (removable): Standard Ebooks, Project Gutenberg.

**Inside a source:**  
Tapping a source opens the OPDS browser — a search-first native UI. A search bar is prominent and immediately focused. Searching queries the server's OpenSearch endpoint and returns results as a list.

Each result shows: cover thumbnail, title, author, series (if available), file format badges (epub confirmed).

Tapping a result opens a detail view: cover, full metadata, description, and a **Download** button. Tapping Download fetches the epub, passes it through the ingestion pipeline, and returns the user to their library with the new book on the shelf.

A **Browse** option is available for navigating the OPDS category hierarchy (by author, series, tag, etc.) but is secondary to search. For large libraries (3,000+ books), browsing the full hierarchy is slow and not the primary workflow — search is.

Pagination is lazy — results load on demand as the user scrolls. The full catalog is never fetched upfront.

---

## 14. iPad-Specific Layout

- Sidebar on the left: Library (with filter tabs and collections nested beneath) and Sources
- Main panel: book grid or list, or OPDS browser
- Sidebar collapses automatically in split-screen multitasking when space is constrained
- Reader always opens full-screen, not inline in the main panel — this avoids significant layout complexity and edge cases. Revisit for a future "two-pane reading" feature if demand warrants it.

---

## 15. Data Model

```swift
// MARK: - Book

@Model
class Book {
    var id: UUID
    var title: String
    var author: String
    var series: String?              // e.g. "Dune"
    var seriesNumber: Double?        // e.g. 1.0
    var language: String
    var publisher: String?
    var epubVersion: String          // "2.0" or "3.0"

    // File location
    var iCloudDrivePath: String?     // relative path within iCloud Drive/Codex/Library/
    var localFallbackPath: String?   // path in Application Support when in localOnly mode
    var storageLocation: StorageLocation  // .iCloudDrive | .localOnly

    // Cover
    var coverCachePath: String?      // path in Application Support/covers/

    // Metadata
    var fileSize: Int64
    var wordCountEstimate: Int?
    var dateAdded: Date
    var lastReadDate: Date?
    var lastReadDeviceName: String?

    // Reading state
    var readingProgress: Double      // 0.0 to 1.0 (of full epub, or of customEndPoint if set)
    var isFinished: Bool
    var customEndPoint: Double?      // user-defined end point (0.0 to 1.0) — overrides full epub length
    var didNotFinish: Bool           // set by "Remind me next time" toggle
    var didNotFinishDate: Date?      // when the flag was set

    // Organisation
    var collectionIDs: [UUID]

    // iCloud file state (refreshed by NSMetadataQuery monitoring)
    var iCloudFileState: ICloudFileState

    // Bookshelf appearance
    var spineColour: String?         // hex colour extracted from cover at ingestion, used for spine background
    var spineTextIsLight: Bool       // true = white text on spine, false = dark text; derived from spineColour luminance

    // Sidecar
    var sidecarLastWritten: Date?
}

// MARK: - Supporting enums

enum StorageLocation: String, Codable {
    case iCloudDrive
    case localOnly
}

enum ICloudFileState: String, Codable {
    case synced           // local copy present and uploaded
    case uploading        // local copy present, upload in progress
    case uploadError      // local copy present, upload stuck
    case cloudOnly        // no local copy, available in iCloud
    case downloading      // download in progress
    case downloadError    // download stuck or failed
    case localOnly        // not in iCloud (StorageLocation == .localOnly)
    case missing          // no local copy and no iCloud copy — ghost record
}

// MARK: - Collection

@Model
class Collection {
    var id: UUID
    var name: String
    var isSmartCollection: Bool
    var smartFilter: SmartFilter?    // only for smart collections
    var bookIDs: [UUID]              // only for manual collections
    var dateCreated: Date
    var sortOrder: Int               // user-defined display order
}
```

---

## 16. Performance Requirements

- Library loads and is scrollable in < 500ms with 3,000+ books
- Cover images loaded lazily, cached in memory (NSCache), never loaded ahead of the visible viewport
- Placeholder shown for covers still being extracted
- Spine colour extraction runs once at ingestion time, on a background thread, and is stored in the book record — never computed at render time
- The cover-to-spine `scrollTransition` animation must be smooth at 60fps on an iPhone 12 or newer. If performance is a concern during development, the rotation curve can be simplified without compromising the core effect
- Sort and filter run on a background thread; UI updates on completion, < 100ms for any collection size
- iCloud state badges update reactively as NSMetadataQuery delivers changes — no polling

---

## 17. Open Questions

- **Shelf wood aesthetic:** Textured/photorealistic vs flat/modern-skeuomorphic. Decision deferred — easy to swap between approaches since the shelf surface is a contained rendering component. Multiple wood styles may be offered as a setting (different woods, different tones). Decide during early visual development.
- **Number of cover-out books per shelf:** Calculated from available width, not hardcoded. Exact formula (minimum cover width, padding) to be determined during layout implementation.
- **Custom collections in v1:** Decision deferred to build time. Architecture supports them; UI may ship without them if they add significant complexity.
- **Series grouping / Series shelf:** Should all books in a series the user owns get their own automatic shelf? This would complement the "Up Next" logic naturally. Nice-to-have for v1.1.
- **Cover-to-spine rotation curve:** The exact easing function (linear, ease-in, custom Bezier) and the face-swap threshold angle will be tuned visually during development. Document the final values as constants in the code.
- **Spine font size and width:** Uniform across all shelves. Default value TBD during visual development. Configurable in Advanced Settings → Library → Spine Width.

---

*Module status: Directive revised — bookshelf view, cover/spine transition, shelf structure, CoverFlow mode, and tap/long-press interaction model fully specified*  
*Last updated: April 2026*
