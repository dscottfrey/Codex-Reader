# Codex — Module 2: Ingestion Engine Directive

**Module:** Ingestion Engine  
**Priority:** High — without books, there is nothing to read  
**Dependencies:** Library Manager (books land in the library after ingestion), Share & Transfer (AirDrop receive path shares this pipeline)

---

## 1. Purpose

The Ingestion Engine handles every path by which an epub file enters Codex and becomes part of the user's library. The design is shaped by a real-world workflow: a Calibre library, served by an OPDS-compatible server (COPS, Calibre-Web, Lazy Librarian, or similar), accessed from iPhone and iPad — including from a local network with no internet access.

The guiding principle: **wherever the epub is, one tap puts it on the shelf.**

---

## 2. The Primary Workflow — OPDS Sources

### 2.1 What OPDS Is

OPDS (Open Publication Distribution System) is a simple, standardized XML catalog format used by personal ebook servers to publish their libraries. It supports browsing, searching, and downloading. Every major Calibre frontend speaks it:

| Server | OPDS endpoint |
|---|---|
| COPS | `/index.php/feed` |
| Calibre-Web / Calibre-Web Automated | `/opds` |
| Lazy Librarian | `/opds` |
| Standard Ebooks | `https://standardebooks.org/feeds/opds` |
| Project Gutenberg | `https://gutenberg.org/catalog/...` |

Codex implements OPDS once and works with all of them, now and for any future server the user adopts.

### 2.2 Book Sources — Configured in Settings

The user maintains a named list of OPDS sources in Codex Settings. Each source has:

- **Name** — a friendly label (e.g., "Home Library", "Camper", "Standard Ebooks")
- **URL** — the OPDS feed root (e.g., `http://192.168.1.10/index.php/feed`)
- **Credentials** — optional username and password, stored in the iOS Keychain (never in plain text)

Multiple URLs can point to the same underlying library (e.g., a local IP for home use and a Tailscale IP for remote access). The user simply adds both as separate sources or switches the URL when needed.

**Pre-configured default sources** (shipped with the app, user can remove):
- Standard Ebooks
- Project Gutenberg

These ensure the app is immediately useful to anyone, even before a personal server is configured.

### 2.3 OPDS Browser — Search-First UI

OPDS sources are accessed from a **Sources** panel in the Library (a tab or sidebar entry, separate from the local shelf). Tapping a source opens a native Codex interface — not a web view.

Because the primary use pattern is searching rather than browsing hierarchies, the interface is **search-first**:

- A search bar is prominent and focused immediately on opening a source
- Typing queries the OPDS OpenSearch endpoint and returns results as a list
- Each result shows: cover thumbnail, title, author, series (if available)
- Tapping a result shows a detail view: full metadata, description, and a **Download** button
- Tapping Download fetches the epub and passes it to the ingestion pipeline (§5)
- A "Browse" option is available for users who want to explore by category/author/series, but it is secondary to search

**Pagination:** OPDS feeds are paginated by spec. Codex loads results on demand as the user scrolls — never fetches the entire catalog upfront. A 3,000-book library has no performance impact.

**Offline/local network:** OPDS sources work on any network the device can reach, including a local Wi-Fi network with no internet access (e.g., a Calibre instance running on a laptop in a camper). There is no requirement for internet connectivity.

### 2.4 App Store Positioning

The OPDS approach is deliberately chosen over an embedded web browser with login support for commercial sites, for one important reason: **OPDS has no commerce layer.** It is a read-only catalog protocol for accessing books you already own on a server you control. There is no purchase flow, no payment, no Apple's-cut implication. This keeps Codex clearly outside the territory of App Store guideline 3.1.1 (alternative payment systems).

Users who purchase books from external stores (e.g., Baen Books) handle that purchase outside Codex — via their browser and their computer — then add the book to their Calibre library. Codex never touches the commerce step.

---

## 3. iCloud Drive Drop Folder

**Flow:** On a Mac (or any device with access to iCloud Drive), the user drops one or more epub files into a designated Codex folder. Codex detects the new files and automatically ingests them — no app open, no tap required on the iOS side.

**Implementation:**

- Codex creates and owns a folder at `iCloud Drive / Codex / Inbox /`
- On iOS, Codex monitors this folder using `NSMetadataQuery` with an iCloud Drive scope, which delivers notifications when new files appear in the folder
- On receiving a notification, Codex copies the epub into its local storage, runs it through the ingestion pipeline (§5), and removes it from the Inbox folder (the Inbox is a drop zone, not a permanent home)
- Monitoring runs when the app is in the foreground; a check also runs on every app launch and foreground transition, to catch files dropped while the app was closed

**Result:** The user drags epubs into a Finder folder on their Mac. Next time they open Codex on any device, the books are on the shelf. This also replaces the USB cable / bulk import workflow for large transfers — drag a folder of epubs into the Codex Inbox on the Mac and walk away.

---

## 4. One-Off Import Paths

These paths handle individual epub files arriving from any source outside a configured OPDS server. They all funnel into the same ingestion pipeline (§5).

### 4.1 System Share Sheet ("Open in Codex")

When an epub file is encountered in any other app — Safari, Mail, Files, a third-party cloud storage app — the user taps Share → "Open in Codex" (or "Copy to Codex"). Codex receives the file and ingests it.

**Implementation:** Register Codex as a handler for the `org.idpf.epub-container` UTI in `Info.plist`. Implement `application(_:open:options:)` to receive the file. This covers Safari downloads, email attachments, and Files app sharing automatically.

### 4.2 AirDrop — From Any Source

When an epub is AirDropped to the device from any source — another iPhone, a Mac, or another device running Codex — iOS presents "Open in Codex" (or opens Codex directly if it is the only epub handler). The file enters the ingestion pipeline.

**No special implementation needed** beyond the UTI registration in §4.1. AirDrop is handled by the system.

**Codex-to-Codex AirDrop:** When a user shares a book from another Codex instance via the Share & Transfer module, the receiving device handles it through this same path. There is no special Codex-to-Codex protocol — it is just an epub arriving via AirDrop. This is intentional. Simple, and it works with any device regardless of what app is installed.

### 4.3 Files App / Document Picker

Within Codex's Library view, an "Add Book" button opens a `UIDocumentPickerViewController`. The user browses iCloud Drive, On My iPhone, or any connected third-party storage and selects one or more epub files. Supports multi-select.

### 4.4 Calibre "Connect to Folder" (No Code Required)

Calibre has a built-in feature — **Preferences → Sharing → Connect to Folder** — that treats any folder on disk as a device. Once pointed at the Codex iCloud Drive Inbox folder, Calibre's "Send to Device" menu copies books there directly, exactly as if sending to a Kindle or Kobo.

On a Mac with iCloud Drive enabled, the Codex Inbox path is:
`~/Library/Mobile Documents/com~apple~CloudDocs/Codex/Inbox/`

The workflow then becomes: right-click a book in Calibre → Send to Device → book appears on the Codex shelf. No companion app, no custom protocol, nothing to build. This is a user-configured convenience that works entirely through the iCloud Drive drop folder (§3), which Codex already monitors.

**This requires no Codex development.** It should be documented in user-facing setup instructions once the app ships.

---

## 5. Ingestion Pipeline

All paths above deliver an epub file (or a ZIP containing one). Every file passes through this shared pipeline:

```
File received (any path above)
    ↓
ZIP check: if the file is a .zip, unzip it and look for .epub files inside
    • One epub found → proceed with that epub
    • Multiple epubs found → present a picker: "This archive contains X books. Select which to add."
    • No epub found → error (see §6)
    ↓
Validate: confirm the file is a valid epub
    (check for ZIP structure, presence of container.xml, readable OPF manifest)
    ↓
Duplicate check: compare title+author and file hash against existing library
    (see §5.1)
    ↓
Extract metadata: title, author, cover image, language, epub version, word count estimate
    ↓
Generate book UUID
    ↓
Copy epub to local storage: books/{uuid}/book.epub
Save extracted cover: books/{uuid}/cover.jpg
    ↓
Write book record to SwiftData
    ↓
Notify Library Manager → book appears on shelf
Notify Sync Engine → register book in iCloud
    ↓
Done
```

### 5.1 DRM Detection

DRM detection runs as part of the validate step. Codex checks for the two most common epub DRM signatures before doing anything else with the file:

**Adobe ADEPT DRM:** the epub's `META-INF/` directory contains an `encryption.xml` file with a `<enc:EncryptionMethod Algorithm="...">` element referencing Adobe's algorithm URI (`http://ns.adobe.com/adept/...`). If this file and element are present, the epub is Adobe DRM-protected.

**Apple FairPlay (iBooks DRM):** Apple Books' DRM is not publicly documented. In practice, Apple DRM'd books are distributed only through the Apple Books store and cannot be opened in any third-party epub reader regardless. Codex does not need to detect Apple DRM specifically — such files would fail the epub validation step (they are not valid standard epubs) and surface the generic "not a valid epub" error.

**Detection logic:**
```swift
func isDRMProtected(_ epubURL: URL) -> Bool {
    // Check for Adobe ADEPT encryption.xml in the unzipped epub container.
    // Path: META-INF/encryption.xml
    // Presence of this file with Adobe algorithm URI = DRM protected.
    // Returns false if file absent (no DRM) or present but empty / non-Adobe.
}
```

If DRM is detected, the pipeline aborts immediately and shows the "DRM-protected" error from §6. No further processing occurs. The file is not copied to any local storage.

### 5.2 Re-ingestion & Resume Logic

When an incoming epub matches an existing library record, Codex does not silently overwrite or silently resume. It always shows the user what it knows and lets them decide. The matching and prompting logic works in three cases:

---

**Case A — Exact file match (same SHA-256 hash)**

The incoming file is byte-for-byte identical to the one already in the library.

Prompt:
```
"The Left Hand of Darkness"
Last read: Tuesday at 2:34 PM — 47% through

Resume where you left off, or start from the beginning?

[Resume]   [Start from beginning]
```

No file-modification warning is shown. The file is the same.

---

**Case B — Same title + author, different hash, recently read**

The file has changed (edited in Calibre, different epub edition downloaded, re-exported) but the book was opened recently — suggesting this is the same reading session, and the change was intentional.

"Recently" is configurable in Advanced Settings (default: within the last 30 days).

Prompt:
```
"The Left Hand of Darkness"
Last read: Today at 2:34 PM — 47% through
Note: the file appears to have been modified.

Resume where you left off, or start from the beginning?

[Resume]   [Start from beginning]
```

The "note" line is informational only — it does not block the user or demand extra decisions. Annotation misalignment review is surfaced passively in the annotation panel, not at this prompt.

---

**Case C — Same title + author, different hash, not recently read**

The file has changed and the book hasn't been opened in a while — more likely a genuinely different edition.

Prompt:
```
"The Left Hand of Darkness"
Last read: April 2014 — 99% through
This may be a different edition of a book already in your library.

Resume from your previous position, start from the beginning, or add as a separate book?

[Resume]   [Start from beginning]   [Add as new]
```

"Add as new" creates a second library entry, preserving the original record untouched. This is the right option if the user genuinely has two different editions they want to track separately.

---

**Recovery case — same title + author, file broken or unavailable in iCloud**

When the existing library copy is in a broken iCloud state (stuck, evicted, download failed):

```
"The Left Hand of Darkness" is in your library but its file is currently unavailable.

Replace it with this copy?

[Replace]   [Cancel]
```

No "add as new" option — the intent here is clearly to fix a broken file.

---

**"Start from beginning" — what gets cleared**

When the user chooses "Start from beginning," the reading position is always reset. What else gets cleared is governed by Settings → Advanced → Re-ingestion Behaviour:

| Item | Default | Notes |
|---|---|---|
| Reading position | Always reset | Not configurable — this is the point of the choice |
| Bookmarks | Ask at time of choice | User is prompted once per re-ingestion event |
| Highlights | Keep | Highlights are still meaningful even in a re-read |
| Notes | Keep | Same reasoning |

The "ask about bookmarks" prompt at time of choice:
```
Also clear bookmarks for this book?
Highlights and notes will be kept.

[Clear bookmarks]   [Keep bookmarks]
```

All these defaults are tunable in Advanced Settings. A user who always wants a completely clean slate can set highlights and notes to "clear" as well.

### 5.3 ZIP Handling

Some OPDS servers and download sites deliver epub files inside a ZIP archive. The pipeline handles this transparently — the user never needs to unzip manually. If a ZIP contains multiple epubs (uncommon but possible), the user is shown a list and can select which books to add, add all, or cancel.

### 5.4 Cover Extraction

1. Look for the cover image declared in the OPF manifest (`properties="cover-image"`)
2. Fall back to the first image file in the epub if no declared cover
3. Fall back to a generated placeholder: styled text (title + author) on a colored background derived from a hash of the title (consistent color per book, not random)

---

## 6. Error Handling

| Condition | Message shown to user | Action |
|---|---|---|
| File is not a valid epub | "This file doesn't appear to be a valid epub and couldn't be added." | Dismiss |
| ZIP contains no epub | "This archive doesn't contain any epub files." | Dismiss |
| File is DRM-protected | "This epub is DRM-protected. Codex only supports DRM-free epub files." | Dismiss |
| Storage full | "Not enough storage to add this book." | Dismiss, link to iOS Settings → Storage |
| Duplicate detected | "This book may already be in your library." | Replace / Keep Both / Cancel |
| OPDS source unreachable | "Couldn't connect to [Source Name]. Check that the server is running and your device is on the right network." | Dismiss, retry button |
| OPDS search returns no results | "No books found for '[query]'." | Inline, no modal |
| Download fails mid-transfer | "Download interrupted. Try again?" | Retry button |

---

## 7. File Storage Layout

Book epub files live in iCloud Drive, visible to the user as ordinary files. Metadata (reading position, annotations, settings) lives in SwiftData and syncs via CloudKit separately.

```
iCloud Drive/
└── Codex/
    ├── Inbox/          ← drop zone: files here are ingested then removed
    └── Library/        ← permanent home for all epub files
        ├── Le Guin, Ursula K. - The Left Hand of Darkness.epub
        ├── Wolfe, Gene - The Book of the New Sun.epub
        └── ...
```

**Filename format:** `{Author Last, First} - {Title}.epub`
Filenames are human-readable and browsable in Finder. Special characters illegal in filenames (`/ : * ? " < > |`) are stripped or replaced with a dash. If two books produce the same filename after sanitization, a number is appended: `...Title (2).epub`.

**Cover images** are stored in Application Support (not iCloud Drive), since they are generated/extracted by Codex and are not user files:
```
Application Support/
└── covers/
    └── {uuid}.jpg      ← one per book, keyed by SwiftData book ID
```

**Why epub files go in iCloud Drive but covers don't:** The epub is the user's file — they should be able to see it, copy it, and recover it independently of the app. The cover is a derived asset that Codex can regenerate at any time from the epub. There is no value in cluttering iCloud Drive with it.

---

## 8. iCloud Resilience & Recovery

This section exists because iCloud Drive is not always reliable. Files get stuck uploading or downloading. The service occasionally enters broken states for specific files or for the account as a whole. Apple Books.app offers no escape from these situations. Codex does.

**The foundational rule: Codex never holds a book hostage to iCloud.**

### 8.1 Storage Location Per Book

Every book in SwiftData has a `storageLocation` property:

```swift
// Every book knows where its epub file actually lives.
// This determines how Codex looks for it and what recovery options are shown.
enum StorageLocation {
    case iCloudDrive(path: String)   // normal state: file is in iCloud Drive/Codex/Library/
    case localOnly(path: String)     // fallback state: file is in local Application Support only
}
```

A book starts as `.iCloudDrive`. It can be demoted to `.localOnly` by the user when iCloud is being difficult. It can be promoted back to `.iCloudDrive` when the user is ready to re-upload.

### 8.2 iCloud File States

Codex monitors each book's iCloud Drive file for the following states, using `URLResourceKey` attributes. These states are shown in the Library UI per book:

| State | What Codex shows | What the user can do |
|---|---|---|
| **Synced** (local + uploaded) | Nothing, clean | "Remove local copy" |
| **Uploading** | Small upload indicator on cover | "Force re-upload", "Keep local only" |
| **Upload stuck / error** | Warning badge on cover | "Force re-upload", "Keep local only" |
| **Cloud-only** (evicted) | Cloud icon on cover | Tap to download, "Keep on device" |
| **Downloading** | Progress bar on cover | Cancel |
| **Download stuck / error** | Warning badge on cover | "Retry download", "Replace file…" |
| **Local only** (iCloud bypassed) | Small device icon on cover | "Upload to iCloud" |
| **Offline, local copy present** | Nothing, reads normally | — |
| **Offline, cloud-only** | Lock icon on cover | Nothing until back online |

### 8.3 "Keep on Device" — Preventing Eviction

The user can mark any book as **Keep on Device**. This pins the epub file to local storage and instructs iCloud Drive never to evict it.

Implementation: call `FileManager.default.startDownloadingUbiquitousItem(at:)` to ensure a local copy exists, then set the `URLResourceKey.ubiquitousItemIsExcludedFromSyncKey` appropriately. The book is then readable offline regardless of iCloud state.

"Keep on Device" is accessible from the book context menu in the Library and from the Book Detail view.

### 8.4 Manual File Replacement — The Escape Hatch

When a book's iCloud copy is broken, stuck, or otherwise unavailable, the user should never be blocked from reading it. The escape hatch:

**From the Book Detail view or context menu:** "Replace File…"
- Opens a document picker (or accepts an AirDrop / share sheet)
- User supplies a fresh copy of the epub from any source
- Codex validates the file (checks it's the same book by title+author or hash)
- Copies the fresh file to the book's iCloud Drive path, overwriting whatever is there
- Immediately marks the local copy as present and readable
- iCloud will re-sync from the fresh local copy when it next cooperates

This means if a book is stuck on one device, the user can AirDrop the epub from another device (or from the Mac via Finder), use "Replace File…", and it is immediately readable. iCloud is bypassed for the reading step and catches up on its own schedule.

### 8.5 "Keep Local Only" — Temporary iCloud Bypass

From the book context menu: **"Keep Local Only"**

- Moves the epub from iCloud Drive to local Application Support
- Updates the book's `storageLocation` to `.localOnly`
- Book is readable immediately regardless of iCloud state
- A "Upload to iCloud" option appears in the context menu to reverse this when ready

This is the nuclear option for when iCloud is being difficult with a specific book. It removes the file from iCloud's reach entirely until the user decides to put it back.

### 8.6 Batch Recovery

If iCloud is having a systemic bad day (not just one book), the user can go to **Settings → iCloud → "Keep All Books Local"** which moves all epub files from iCloud Drive to local storage in one action. A corresponding "Restore All to iCloud" option re-uploads everything when things are working again.

This is the escape hatch for the "iCloud is completely broken today" scenario.

---

## 9. Error Handling

| Condition | Message shown to user | Action |
|---|---|---|
| File is not a valid epub | "This file doesn't appear to be a valid epub and couldn't be added." | Dismiss |
| ZIP contains no epub | "This archive doesn't contain any epub files." | Dismiss |
| File is DRM-protected | "This epub is DRM-protected. Codex only supports DRM-free epub files." | Dismiss |
| Storage full | "Not enough storage to add this book." | Dismiss, link to iOS Settings → Storage |
| Standard duplicate detected | "This book may already be in your library." | Replace / Keep Both / Cancel |
| Broken-copy duplicate detected | "This book is in your library but its file is unavailable. Replace it?" | Replace / Cancel |
| OPDS source unreachable | "Couldn't connect to [Source Name]. Check the server is running and your device is on the right network." | Dismiss, retry button |
| OPDS search returns no results | "No books found for '[query]'." | Inline, no modal |
| Download fails mid-transfer | "Download interrupted. Try again?" | Retry button |
| iCloud upload stuck | Warning badge on book cover | "Force re-upload" / "Keep local only" |
| iCloud download stuck | Warning badge on book cover | "Retry download" / "Replace file…" |

---

## 10. What Is Deliberately Not Here

- **Embedded web browser with bookstore login** — removed to stay clear of App Store guideline 3.1.1. Commerce happens outside Codex, in Calibre.
- **Multipeer Connectivity / Codex-to-Codex discovery protocol** — AirDrop via the system share sheet handles this without a custom protocol. Revisit in v1.1 if needed.
- **USB / iTunes file sharing** — not implemented in v1. The iCloud Drive Library folder replaces this; books are visible in Finder without any special file sharing mode.
- **Calibre wireless device companion Mac app** — considered and set aside. Calibre's built-in "Connect to Folder" feature achieves the same result using the existing iCloud Drive Inbox, with no companion app to build or maintain.

- **Embedded web browser with bookstore login** — removed to stay clear of App Store guideline 3.1.1. Commerce happens outside Codex, in Calibre.
- **Multipeer Connectivity / Codex-to-Codex discovery protocol** — AirDrop via the system share sheet handles this without a custom protocol. Revisit in v1.1 if direct device-to-device transfer without AirDrop is needed.
- **USB / iTunes file sharing** — not implemented in v1. The iCloud Drive drop folder replaces this use case more conveniently.
- **Calibre wireless device companion Mac app** — considered and set aside. Calibre's built-in "Connect to Folder" feature achieves the same result (send from Calibre → appear on shelf) using the existing iCloud Drive Inbox, with no companion app to build or maintain.

---

---

## Deferred Review Note

**Cross-module overlap to resolve:** The Library Manager directive (§13 Sources Tab) now contains a full specification of the OPDS browser UI — search-first native interface, lazy pagination, source management, download flow. The Ingestion Engine directive (§2–§5) covers the same OPDS sources from the pipeline and data model side. Before implementation begins, review both directives together to confirm there is no duplication of responsibility and that the boundary between "UI for browsing sources" (Library Manager) and "pipeline for ingesting from sources" (Ingestion Engine) is cleanly drawn. The Sources tab UI may be better housed entirely in the Library Manager directive, with the Ingestion Engine retaining only the download-and-ingest pipeline logic.

*Module status: Directive rewritten — reflects OPDS-first architecture. Cross-module review with Library Manager pending.*  
*Last updated: April 2026*
