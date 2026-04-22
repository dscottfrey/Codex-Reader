# Codex — Module 4: Sync Engine Directive

**Module:** Sync Engine  
**Priority:** High — unreliable sync is one of the primary failures of Apple Books  
**Dependencies:** Library Manager (library state to sync), Annotation System (annotations to sync), Rendering Engine (reading position to sync)

---

## 1. Purpose

The Sync Engine keeps all of a user's Codex data consistent across their iPhone and iPad (and any future Apple devices running Codex) without requiring any user action. It syncs reading position, bookmarks, highlights, notes, library metadata, and reader settings.

The design philosophy here is direct opposition to Apple Books: **sync should be silent, automatic, and reliable.** The user should never think about sync. They should simply pick up their iPad, open a book, and be exactly where they left off on their iPhone.

---

## 2. What Gets Synced

Codex uses two parallel sync mechanisms. They are complementary and handle different kinds of data:

**iCloud Drive** syncs the epub files themselves. This is automatic and requires no Codex code — it is a consequence of storing files in `iCloud Drive/Codex/Library/`. Add a book on one device, it appears on all devices. This is high priority and fully solved by the storage architecture.

**CloudKit** (via SwiftData) syncs all reading state and metadata. This is what Codex actively manages.

| Data type | Mechanism | Priority | Conflict strategy |
|---|---|---|---|
| Book epub files | iCloud Drive (automatic) | Critical | iCloud Drive handles this — last write wins at the file level |
| Reading position (chapter + offset) | CloudKit | Critical | Latest write wins |
| Recently active books stack | CloudKit | Critical | Latest write wins per entry |
| Bookmarks | CloudKit | High | Merge — all bookmarks from all devices are kept |
| Highlights | CloudKit | High | Merge — all highlights kept; overlaps flagged |
| Notes | CloudKit | High | Merge — same as highlights |
| Book metadata (title, author, cover edits) | CloudKit | Medium | Latest write wins |
| Per-book typography (mode + overrides) | CloudKit | Medium | Latest write wins |
| Library organisation (collections, sort order) | CloudKit | Medium | Latest write wins |
| Reader settings (font, size, margins, etc.) | CloudKit | Medium | Latest write wins |
| Cover images | Not synced | — | Derived assets; regenerated locally from the epub file |

---

## 3. Technology: CloudKit

Codex uses **CloudKit** (specifically the private database) for all sync. This choice means:

- No server to build, maintain, or pay for.
- Sync is tied to the user's Apple ID — all devices signed into the same account sync automatically.
- Data is stored in Apple's infrastructure, which the user already trusts.
- CloudKit handles conflict detection, push notifications, and retry logic at the framework level.

**CloudKit database type used:** Private Database (each user's data is visible only to them, stored in their iCloud account).

**CloudKit record types** map to the app's data model (see §4).

---

## 4. CloudKit Schema

### 4.1 ReadingPosition Record

```
RecordType: ReadingPosition
Fields:
  - bookID (String)           → the book's UUID
  - chapterHref (String)      → the href of the current chapter in the epub spine
  - scrollOffset (Double)     → normalized scroll offset within the chapter (0.0–1.0)
  - lastUpdated (Date)        → timestamp of last position update
  - deviceName (String)       → name of the device that wrote this record (for debugging)
```

One record per book. Keyed by `bookID`. If two devices write simultaneously, latest `lastUpdated` wins.

### 4.2 Annotation Record

```
RecordType: Annotation
Fields:
  - annotationID (String)     → UUID for this annotation
  - bookID (String)           → which book
  - type (String)             → "highlight" | "note" | "bookmark"
  - chapterHref (String)      → which chapter
  - startOffset (Int)         → character offset from start of chapter text (matches Annotation System §5 data model)
  - endOffset (Int)           → character offset; equals startOffset for bookmarks
  - highlightColor (String)   → hex color (for highlights)
  - noteText (String)         → text of note (may be empty for pure highlights)
  - createdAt (Date)
  - deletedAt (Date?)         → soft-delete: set this instead of removing the record
```

Each annotation is a separate record. Sync merges (never overwrites) annotation sets.

### 4.3 Book Metadata Record

```
RecordType: BookMetadata
Fields:
  - bookID (String)           → UUID
  - title (String)
  - author (String)
  - coverAsset (CKAsset?)     → cover image (only if user replaced default cover)
  - isFinished (Bool)
  - readingProgress (Double)  → 0.0–1.0
  - dateAdded (Date)
  - lastReadDate (Date?)
  - collectionIDs (List<String>)
  - typographyMode (String)         → "publisherDefault" | "userDefaults" | "custom" (see Rendering Engine §7.2)
  - typographyOverrides (Data?)     → JSON-encoded BookReaderOverrides blob; nil when typographyMode != "custom" (see Rendering Engine §7.3)
  - lastUpdated (Date)
```

### 4.4 ReaderSettings Record

```
RecordType: ReaderSettings
Fields:
  - fontSize (Double)
  - fontFamily (String)
  - useBookFonts (Bool)
  - lineSpacing (Double)
  - letterSpacing (Double)
  - textAlignment (String)
  - theme (String)
  - pageTurnStyle (String)
  - marginTop (Double)
  - marginBottom (Double)
  - marginLeft (Double)
  - marginRight (Double)
  - lastUpdated (Date)
```

One record per user (not per device). Latest write wins. This means settings changes on one device propagate to all others.

---

## 5. Book File Sync — Solved by Storage Architecture

Book epub files are stored in `iCloud Drive/Codex/Library/`. iCloud Drive syncs this folder across all devices signed into the same Apple ID automatically, with no Codex code required. A book added on the iPhone appears on the iPad. A book dropped into the folder from a Mac appears on both.

This is the complete solution to book file sync. There is nothing for the Sync Engine to do here beyond what is already described in the Ingestion Engine directive (§3 — iCloud Drive drop folder, §8 — iCloud resilience and recovery).

The "evicted / not downloaded" state (where iCloud Drive has removed the local copy to save space) is handled in the Ingestion Engine directive §8. Codex shows the cloud state per book in the Library and provides manual controls to force download or keep a book pinned locally.

---

## 6. Sync Behavior

### 6.1 Push Notifications (CKSubscription)

- Codex registers a `CKQuerySubscription` on each record type so that when another device writes a change, the local device receives a silent push notification.
- On receiving the push, the Sync Engine fetches changed records and updates the local database.
- This is the mechanism that makes sync feel instant — when the user finishes on their iPhone and picks up their iPad, within seconds the iPad updates.

### 6.2 Periodic Pull (Fallback)

- On app launch and when the app returns to foreground, the Sync Engine performs a fetch of recently changed records (using `CKFetchRecordZoneChangesOperation` with a change token).
- This catches any changes missed during periods when push notifications were unavailable (e.g., device was offline).

### 6.3 Offline Behavior

- All reads come from the local database first.
- Writes go to the local database immediately, then are queued for CloudKit sync when connectivity is available.
- CloudKit's `CKModifyRecordsOperation` handles retry automatically. Codex does not need to implement its own retry logic.

### 6.4 Conflict Resolution

| Situation | Resolution |
|---|---|
| Same reading position updated on two devices before sync | Latest `lastUpdated` timestamp wins |
| Annotation added on device A and B simultaneously | Both are kept (merge strategy) |
| Annotation deleted on device A, modified on device B | Deletion wins (soft-delete `deletedAt` takes precedence) |
| Book metadata changed on two devices | Latest `lastUpdated` wins |
| Reader settings changed on two devices | Latest `lastUpdated` wins |

---

## 7. App Open Behaviour — Cross-Device Resume

This section describes what Codex does when the user opens the app on a device, particularly after having read on a different device.

**Assumption:** One Apple ID = one user. Two people sharing an Apple ID is a known failure pattern and is not a supported use case. Each iCloud account is treated as a single reader.

### 7.1 The Recently Active Books Stack

Codex maintains a **stack of up to 5 recently active books**, ordered by most-recently-opened across all devices. This stack is synced via CloudKit so every device has the same view of recent reading activity.

Each entry in the stack carries:
- Book ID and title
- The device it was last read on
- The reading position at last close
- The timestamp of last read

The stack powers both the app-open behaviour and the quick-switch gesture (§7.3).

### 7.2 "Follow Me" vs "Stay Here" — The Switch

A single prominent toggle in Settings controls what happens when Codex opens:

**Follow Me** — Codex opens to the most recently read book across all devices, at the position it was left. If the user was reading on the iPad and picks up the iPhone, the iPhone opens to the same book at the same place. Best for a single reader who moves between devices mid-chapter.

**Stay Here** — Codex opens to the most recently read book on *this device*, regardless of what was happening on other devices. Best for someone who reads different books on different devices and doesn't want them to interfere with each other.

Default: **Follow Me.** This is the more surprising and delightful behaviour for new users, and the one that most directly addresses the "pick up and continue" use case.

The setting is per-device — iPhone and iPad can have different settings if the user prefers.

### 7.3 Time-Assisted Middle Ground (Advanced Setting)

For users who want neither pure Follow Me nor pure Stay Here, Advanced Settings offers a time threshold:

> **"Switch to Follow Me if other device was read within: [1 hour / 4 hours / 1 day / 1 week]"**

Logic: if the other device's last-read timestamp is within the threshold, behave as Follow Me (you just put it down — follow you). If it's older than the threshold, behave as Stay Here (you've moved on — stay put).

Default threshold: **4 hours.** Configurable in Advanced Settings.

This option is only surfaced when the main switch is set to Follow Me — it refines Follow Me rather than replacing it.

### 7.4 Quick-Switch Gesture — The Recently Active Stack

Regardless of the Follow Me / Stay Here setting, the user can always quickly navigate the recently active stack without going to the library.

**Mechanism:** A button in the reader's navigation bar (a small "recently read" icon, visible when the nav bar is shown) opens a compact panel listing the 5 most recently active books with cover thumbnails, title, and last-read time. Tapping one opens it at its last position.

A **three-finger swipe** (left or right) on the reading view cycles through the stack — forward/backward through recent books — without opening the library. A brief overlay confirms which book you've switched to.

Both the button and the gesture are always available, regardless of mode. The gesture can be disabled in Accessibility Settings for users who find it triggering accidentally.

### 7.5 Future: Apple Intelligence Assist (Post-v1)

A note for future consideration, not a v1 feature:

Apple Intelligence (on-device ML, no data leaving the device) could learn patterns in the user's behaviour — which device they tend to read which books on, what time of day they switch devices, how long a gap before "follow me" stops making sense — and suggest the optimal mode automatically, or adjust the time threshold silently. The user would see a suggestion ("Looks like you read different books on iPad and iPhone — want to switch to Stay Here?") with an easy accept or dismiss.

The v1 architecture should not preclude this — the data it would need (timestamps, device names, book IDs) is already in the stack. The intelligence layer would sit on top without requiring structural changes.

Guard rails for any future AI assist: the user can always see what mode they're in, always override it with one tap, and the AI never changes the setting silently without the user accepting a suggestion.

---

## 8. iCloud Account State Handling

The app must handle the following iCloud states gracefully:

| State | App behavior |
|---|---|
| Signed in, sync available | Sync runs normally, silently |
| Signed in, iCloud Drive disabled for Codex | Show one-time prompt asking user to enable iCloud for Codex in Settings |
| Not signed in to iCloud | Sync is unavailable; app works fully locally; a subtle note in Settings explains that sync requires iCloud |
| iCloud quota full | Log the error; don't bother the user; retry when quota clears |
| Network unavailable | Queue changes locally; sync when connectivity returns |

The app must **never** crash or degrade reading functionality due to a CloudKit error. Sync is a background concern — reading is always primary.

---

## 9. Privacy & Data

- All CloudKit private database data is encrypted in transit and at rest by Apple.
- Codex does not send data to any Codex-owned server. There is no Codex backend.
- No analytics or telemetry data is sent anywhere.
- The Codex privacy policy (to be written before App Store submission) should reflect this.

---

## 10. Implementation Notes

- **Deployment target is iOS 17+. SwiftData is the data layer. ✅ Decided.**
- Use `ModelContainer` configured with a CloudKit container identifier. SwiftData automatically mirrors the model store to the CloudKit private database — no manual `CKModifyRecordsOperation` boilerplate required.
- The CloudKit schema in §4 describes the logical data model. SwiftData's CloudKit integration manages the actual CloudKit record types at runtime. Verify the generated schema in the CloudKit Dashboard during development.
- For any sync behavior that SwiftData's automatic sync does not cover (e.g., fine-grained conflict resolution beyond last-write-wins), drop down to `CKModifyRecordsOperation` only for those specific cases.
- All `@Model` classes must conform to SwiftData's requirements: value types for properties where possible, no retain cycles.

---

## 11. Portable Data Export — Your Data, Independent of Apple

CloudKit backs up reading data within Apple's infrastructure. That is not the same as the user owning their data. This section describes a parallel, Apple-independent backup that the user controls completely.

### 11.1 What It Is

A **Codex Library Export** is a single JSON file containing all reading data for all books. It is:

- Human-readable in any text editor
- Stored wherever the user chooses — iCloud Drive, Dropbox, a USB drive, emailed to themselves
- Completely independent of Apple, CloudKit, and Codex being installed
- Importable back into Codex at any time to restore or merge data
- The canonical answer to "what happens to my data if CloudKit fails, if I leave Apple, or if I just want a backup I trust?"

### 11.2 What the Export Contains

```json
{
  "exportVersion": 1,
  "exportDate": "2026-04-20T14:32:00Z",
  "exportedBy": "Codex vX.X",
  "books": [
    {
      "id": "uuid-string",
      "title": "The Left Hand of Darkness",
      "author": "Le Guin, Ursula K.",
      "language": "en",
      "fileHash": "sha256-of-epub",
      "dateAdded": "2024-01-15T10:00:00Z",
      "lastOpenedDate": "2026-04-20T14:30:00Z",
      "readingProgress": 0.47,
      "isFinished": false,
      "storageLocation": "iCloudDrive",
      "readingPosition": {
        "chapterHref": "OEBPS/chapter07.xhtml",
        "scrollOffset": 0.312,
        "lastUpdated": "2026-04-20T14:30:00Z"
      },
      "annotations": [
        {
          "id": "uuid-string",
          "type": "highlight",
          "chapterHref": "OEBPS/chapter03.xhtml",
          "startOffset": 4821,
          "endOffset": 4903,
          "highlightColor": "yellow",
          "noteText": "This is the line I keep coming back to",
          "createdAt": "2026-02-10T09:15:00Z"
        }
      ],
      "bookmarks": [
        {
          "id": "uuid-string",
          "chapterHref": "OEBPS/chapter05.xhtml",
          "scrollOffset": 0.75,
          "label": "End of the council scene",
          "createdAt": "2026-03-01T20:00:00Z"
        }
      ]
    }
  ],
  "readerSettings": {
    "fontSize": 18.0,
    "fontFamily": "Georgia",
    "theme": "light",
    "pageTurnStyle": "slide",
    "marginTop": 20,
    "marginBottom": 20,
    "marginLeft": 24,
    "marginRight": 24,
    "lineSpacing": 1.4
  },
  "collections": []
}
```

The export does **not** contain epub files — those are already in iCloud Drive as real files the user can see and copy independently.

### 11.3 Exporting

**Settings → Advanced → Export Library Data**

Generates the JSON file and presents the system share sheet. The user saves it wherever they want: Files app, iCloud Drive, email, AirDrop to Mac, USB via Finder.

A suggested filename is provided: `Codex-backup-2026-04-20.json`

Export can also be triggered from **Settings → Advanced → Scheduled Backup** to run automatically on a set interval (daily, weekly, monthly) and save to a chosen iCloud Drive location. This is a set-and-forget safety net.

### 11.4 Importing

**Settings → Advanced → Import Library Data**

Opens a document picker. User selects a previously exported JSON file. Codex presents options:

```
Import "Codex-backup-2026-04-20.json"

This backup contains 312 books and 1,847 annotations.

How would you like to import it?

[Merge with current library]
[Replace current library]
[Cancel]
```

**Merge:** Imported records are added to or updated in the existing library. Books already present are updated only if the imported record has a more recent `lastOpenedDate`. Annotations are merged (no duplicates by ID).

**Replace:** Current library data is cleared and replaced entirely with the imported data. Requires a confirmation step. The epub files in iCloud Drive are not touched — only the SwiftData records are replaced.

### 11.5 Editing as a Power-User Path (v1.1)

Because the export format is plain JSON, a technical user can already edit it directly — fix a stuck reading position, delete unwanted annotations, reset a book's progress — then re-import. This is not a supported or documented workflow in v1, but it works and does not need to be prevented.

A basic in-app editing interface (reset reading position per book, bulk-delete annotations, fix metadata) is a v1.1 goal, once the export/import path proves itself in the field.

---

## 12. Sidecar Files — Belt and Suspenders

### 12.1 What They Are

A `.codex` sidecar file is written alongside each epub in `iCloud Drive/Codex/Library/`. It contains the complete reading state for that one book — position, bookmarks, annotations — as a JSON file. It is a second, independent record of everything CloudKit also stores.

```
iCloud Drive/Codex/Library/
├── Le Guin, Ursula K. - The Left Hand of Darkness.epub
├── Le Guin, Ursula K. - The Left Hand of Darkness.codex   ← sidecar
├── Wolfe, Gene - The Book of the New Sun.epub
└── Wolfe, Gene - The Book of the New Sun.codex
```

Because sidecars live in iCloud Drive alongside the epubs, they sync automatically via iCloud Drive — the same mechanism as the epub files. They are not a local-only backup; they are a second sync path that is entirely independent of CloudKit.

If CloudKit loses or corrupts reading data, Codex can rebuild from the sidecars. If the sidecars and CloudKit disagree, the most recently written record wins (each sidecar carries a `lastWritten` timestamp).

### 12.2 Write Schedule

Sidecars are written silently, during natural idle moments:
- On every chapter turn
- On the existing 30-second sync timer while reading
- When the app goes to background
- When a book is closed

There is no meaningful performance cost — a heavily annotated book produces a sidecar of perhaps 30–50KB. Writing it is instantaneous.

### 12.3 Default State and Settings

**On by default.** The overhead is negligible and the recovery value is real and permanent.

Settings → Advanced → Sidecar Files:
- **Write sidecar files** — toggle, on by default
- **Sidecar write interval** — matches the main sync timer; configurable (default: 30 seconds)

This is an Advanced setting most users will never see. It is not surfaced in the main Settings screen.

**Note for beta period:** Sidecar files are particularly valuable during beta, when SwiftData or CloudKit edge cases are more likely to surface. The plan is to keep them on permanently after beta, since the cost is negligible and the safety net is real. This decision should be reviewed at the end of the beta cycle — if sidecar files caused any problems during beta, reconsider; if they caused none, leave them on.

### 12.4 Sidecar Lifetime and Orphan Cleanup

**Normal removal:** When a book is removed from the library through Codex, the sidecar is deleted as part of the same operation. The epub and sidecar are treated as a unit.

**Orphaned sidecars:** A sidecar becomes orphaned when its epub is deleted outside of Codex (via Finder or the Files app) without Codex being involved.

Cleanup behaviour:
- On every app launch, Codex scans the Library folder for `.codex` files with no corresponding `.epub`
- Orphaned sidecars enter a **7-day grace period** before deletion — in case the epub is temporarily unavailable due to an iCloud hiccup rather than a deliberate deletion
- After the grace period, orphaned sidecars are deleted silently
- A manual **"Clean up orphaned files"** trigger is available in Settings → Advanced, for users who want to force cleanup immediately

---

## 13. "Finished?" — Defining and Handling Book Completion

### 13.1 The Problem

Epub files often contain content beyond the main text: endnotes, appendices, acknowledgments, indexes, author's notes, and — very commonly — preview chapters of the publisher's next release. A reader who reaches the last page of the main narrative may be at 89% or 94% progress, not 100%, because of this trailing content. Apple Books handles this badly, often locking the book in a permanent near-finished state.

Codex's approach: **never prompt the reader while they're reading.** The "Finished?" question is asked passively, from the library shelf, when the evidence already suggests the book is done.

### 13.2 When "Finished?" Appears on the Shelf

A **"Finished?"** button appears on a book's library card (in both grid and list view) when ALL of the following are true:

- Reading progress is above a threshold (default: **90%**, configurable in Advanced Settings)
- The book has not been opened in longer than a set period (default: **7 days**, configurable in Advanced Settings)
- The book has not already been marked as finished

This combination — nearly done, and you haven't touched it in a week — is strong evidence that you've read what you wanted to read. The button is a quiet nudge, not a notification or a modal.

### 13.3 What "Finished?" Offers

Tapping the button opens a small panel with three independent toggles and a Confirm button. Each toggle defaults to off — nothing happens unless the user actively chooses it.

```
Finished with "The Left Hand of Darkness"?

[ ] Remember that this book ends here
    Saves your current position as this book's end point.
    Useful when preview chapters inflate the page count.
    Remembered permanently — if you re-ingest this book later,
    Codex will know where you consider it to end.

[ ] Remove from shelf
    Deletes the epub and sidecar from your library.
    Your annotations remain in your library export.

[ ] Remind me next time I download this
    If you ingest this book again in future, Codex will note:
    "You didn't finish this last time (April 2026)."

                              [Not yet]   [Confirm]
```

Any combination of toggles is valid — all three on, none on, any pair. "Confirm" with nothing toggled simply marks the book as finished and closes the panel.

### 13.4 "Remember this book ends here" — The Spine Bandaid

Toggle 1 stores the current reading position as a **custom end point** in the book's SwiftData record and sidecar. From that point:

- Progress is calculated as a percentage of the distance to this end point, not the epub's full length
- Reaching the end point triggers the "finished" state, same as reaching the physical end of the epub
- This end point is written into the book's history and persists through deletion and re-ingestion — it is carried in the portable JSON export and will be restored if the book is ever re-added

This is the cleanest fix for the "preview chapters make the book look unfinished" problem, and it requires no cooperation from the epub file itself.

### 13.5 "Remind me next time" — Re-ingestion Hook

Toggle 3 sets a `didNotFinish` flag on the book record, with a timestamp. This flag persists even after the book is removed from the shelf. When the same book (matched by title + author) is re-ingested in future, the re-ingestion prompt includes the reminder:

```
"The Left Hand of Darkness"
Note: you didn't finish this last time (April 2026), at 94%.

Resume from 94%, start from the beginning, or add as a new copy?

[Resume at 94%]   [Start from beginning]   [Add as new]
```

The flag and its timestamp are stored in the SwiftData history record and included in the portable JSON export.

### 13.6 Auto-Detection via Epub Spine (Best Case)

When the epub has clean spine markup, Codex can detect the end of the main content without any user input. The OPF spine distinguishes **linear** items (main reading content) from **non-linear** items (footnotes, supplementary material, preview chapters marked `linear="no"`).

When the user reaches the end of the last linear spine item, Codex softly surfaces a **"Mark as Finished"** option — not a prompt, just a button that appears in the reader nav bar momentarily and then fades. The user can tap it or ignore it entirely.

This is the best-case path when epub spine metadata is correct. The "Finished?" shelf button is the fallback for everything else.

---

## 14. Open Questions

- **Scheduled backup destination:** iCloud Drive is the obvious default for scheduled automatic backups, but the user should be able to choose any Files-accessible location.
- **Reading position sync granularity:** ✅ **Decided:** Sync on chapter turn, on a 30-second timer while actively reading, and immediately when the app goes to background.
- **"Finished?" threshold and idle period:** Defaults are 90% and 7 days. Both configurable in Advanced Settings. Review defaults during beta based on real usage.

---

*Module status: Directive updated — sidecar files, finished state, and shelf completion UI added*  
*Last updated: April 2026*
