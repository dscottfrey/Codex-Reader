# Codex — Module 5: Share & Transfer Directive

**Module:** Share & Transfer  
**Priority:** Medium-High — a key differentiator from Apple Books  
**Dependencies:** Library Manager (source of books to share), Annotation System (source of annotations to export), Ingestion Engine (receiving end of transfers), Rendering Engine (text selection and bracket bookmarks originate there)

---

## 1. Purpose

Codex treats sharing as a natural, frictionless activity. This covers three distinct things:

1. **Sharing the epub file** — sending a book to another device or person
2. **Sharing selected text** — copying or sharing a passage from the current reading session
3. **Exporting annotations** — sharing highlights, notes, and bookmarks as readable text

All three use the same underlying text formatting engine where text content is involved, and all three deliver content via the iOS system share sheet or clipboard. There is no custom sharing infrastructure.

This module covers outgoing sharing. Incoming transfers (receiving a shared epub) are handled by the Ingestion Engine.

---

## 2. Sharing the Epub File

### 2.1 System Share Sheet

**Flow:** Long-press a book in the library → tap "Share" → iOS share sheet appears with the epub file attached. Also accessible from "Share Book…" in the reader's options panel.

AirDrop, iMessage, Mail, Save to Files, and any other installed share destination are all provided free by the system share sheet. No custom sharing code is required beyond presenting `UIActivityViewController` with the epub file URL.

**Key requirement:** the epub file path passed to `UIActivityViewController` must be a directly readable file — copy to a temporary location first if the live iCloud Drive path might be security-scoped or unavailable during the share operation.

**Design decision:** Codex does not implement DRM, does not verify that the recipient "owns" the book, and does not warn about copyright. These are legal responsibilities of the user. Codex is a tool. It does not moralize.

---

## 3. The Text Formatting Engine

All text sharing — whether a short highlighted excerpt or a full annotation export — goes through the same formatting engine. The output of this engine is placed on the iOS clipboard carrying **two representations simultaneously**:

- **Rich text (NSAttributedString / RTF):** preserves bold, italic, and other inline formatting from the epub's HTML. Apps that support rich text paste — Notes, Word, Pages, Mail, and on iOS 17+ Messages — will use this representation and display the formatting correctly.
- **Plain text fallback:** for apps that only accept plain text. Formatting is stripped; content is preserved.

**Attribution:** by default, a plain attribution line is appended to all shared text:

> *— [Book Title], [Author]*

Attribution is appended to both the rich text and plain text representations. Togglable in Advanced Settings (default: on).

**Why not PDF?** Dropped. No clear use case for a PDF of reading excerpts or annotations — it adds implementation cost for a format nobody asks for. Rich text covers the word processor case; plain text covers everything else.

**Markdown:** retained as an optional export format for annotation export only (§5), for users of Obsidian, Notion, Bear, and similar tools. Not a default. Not used for in-reader text sharing.

---

## 4. Sharing Selected Text (In-Reader)

### 4.1 Short Excerpts — Text Selection Callout

For passages that fit on screen, standard iOS text selection applies: long press → drag handles → callout bar. The Share action in the callout opens the share sheet with the selected text formatted via the engine in §3 (rich text + plain text, attribution appended).

A **"Copy with Formatting"** action is also available in the callout, distinct from the standard "Copy" (which copies plain text only). "Copy with Formatting" puts the rich text representation on the clipboard directly, for paste into Notes, Word, Messages, etc.

See Rendering Engine §4.8 for the full callout bar specification.

### 4.2 Long Passages — Highlight Back to Previous

Selecting text across multiple pages by dragging handles is impractical. For longer passages within a chapter, Codex uses the existing highlight system as the mechanism — no new concept required.

**Workflow:**

1. Navigate to the first word of the passage. Long-press it, tap **Highlight** in the callout. A single-word highlight is created at the start position.
2. Read naturally. Navigate forward through the chapter until reaching the end of the passage.
3. Long-press the last word. Tap **Highlight** in the callout. A single-word highlight is created at the end position.
4. Tap the end highlight. The highlight popover includes **"Highlight Back to Previous"**.
5. Tap it. Codex creates a single unified highlight spanning from the start of the nearest prior highlight in the chapter to the end of the tapped highlight. The two anchor highlights are absorbed into the larger one.

The resulting highlight is a normal highlight. All standard highlight actions apply: copy with formatting, share via share sheet, export as text or markdown, add a note, change colour. No special cases, no new UI patterns.

**Anchor pairing:** "Highlight Back to Previous" always connects to the immediately preceding highlight in reading order within the same chapter. There is no ambiguity and no prompt — the pairing is deterministic.

**Chapter boundary rule:** highlights are chapter-scoped. If the passage the user wants to share spans a chapter boundary, "Highlight Back to Previous" is not available across that boundary. Codex shows: *"Highlights can't span chapters. Create a highlight in each chapter separately."* The user creates one highlight in each chapter and shares them individually. Cross-chapter passages are rare enough that this is an acceptable constraint — avoiding the data model complexity of cross-chapter highlights is worth it.

**Full spec for "Highlight Back to Previous"** as an annotation feature lives in the Annotation System directive (Module 6, §3.3). This directive covers the sharing side — once the highlight exists, standard text sharing applies.

---

## 5. Annotation Export

### 5.1 What Gets Exported

A full annotation export for a single book includes all highlights, notes, and bookmarks in reading order, formatted as readable text. Each annotation entry includes:

- The highlighted text (or bookmark label)
- The note text (if any)
- Chapter name and position reference
- Date created (optional — togglable)

### 5.2 Export Formats

| Format | Use case | Default |
|---|---|---|
| **Rich text (.rtf)** | Paste into Word, Pages, Notes, email. Formatting preserved. | ✓ Default |
| **Plain text (.txt)** | Universal fallback. Clean, readable anywhere. | Available |
| **Markdown (.md)** | Obsidian, Notion, Bear, Ulysses, any markdown-based tool. | Available |

PDF export is not offered. Rich text covers the formatted document case; it opens in Word, Pages, and any RTF-capable app.

**Plain text format:**
```
Annotations — The Left Hand of Darkness
Ursula K. Le Guin
Exported: April 20, 2026
────────────────────────────

Chapter 3 · The Mad King

"I certainly was not happy. Happiness has to do with reason, and only reason earns it."
[Note: This is the line I keep coming back to]

Chapter 7 · The Question of Sex

"The unknown is what I'm after — the great mystery."
```

**Markdown format:** same structure, with `##` headers for chapters, `>` blockquotes for highlighted text, and `**bold**` for note labels.

**Rich text format:** the same structure as plain text, with the highlight text rendered in the highlight's colour and notes in a secondary font style. Suitable for pasting directly into a word processor as a formatted document.

### 5.3 Export Access Points

- Library context menu on a book → "Export Annotations"
- Options panel in the reader → "Bookmarks, Highlights & Notes" → Export button
- Annotation review screen → Export button

After tapping Export, a format picker appears (rich text / plain text / markdown), then the share sheet opens with the generated file attached.

### 5.4 Same Engine as Text Sharing

The annotation export uses the same formatting engine as in-reader text sharing (§3). Highlights with bold or italic text in the source epub will have that formatting preserved in both the rich text export and the markdown export. The system is not building a new text pipeline for export — it is reusing the same NSAttributedString conversion used for single-passage sharing.

---

## 6. What Is Not Shared

| Item | Shared? | Reason |
|---|---|---|
| Epub file | Yes — system share sheet | Core sharing use case |
| Text excerpt (short) | Yes — callout → Share or Copy | In-reader text sharing |
| Text excerpt (long) | Yes — bracket bookmarks → Share | Multi-page passage sharing |
| Annotations | Yes — explicit export | User-initiated |
| Reading position | No | Personal device state; synced via CloudKit, not transferred |
| Reader settings | No | Personal preferences; not meaningful to another reader |

---

## 7. Error Handling

| Error | User-facing message | Action |
|---|---|---|
| Epub file not found on disk | "The book file couldn't be found. It may have been removed from iCloud Drive." | Offer Replace File… |
| Annotation export fails | "Couldn't export annotations. Please try again." | Dismiss |
| Bracket text extraction fails (e.g., chapter not loaded) | "Couldn't extract the selected passage. Try opening the book to that page first." | Dismiss |

---

## 8. Privacy

- Share sheet activity may be logged by iOS system analytics. Codex has no control over this.
- No share activity is logged by Codex or sent to any server.
- Bracket bookmark content is never persisted — it exists only in memory while both brackets are placed and is discarded on close.

---

## 9. Open Questions

- **Batch annotation export (all books):** export annotations for every book at once into a folder or single file. Useful for backup. Scope for v1.1.
- **Markdown flavour:** standard CommonMark is the default. If specific tool compatibility (Obsidian callout syntax, Notion block format) becomes a request, add format variants in Advanced Settings.
- **"Highlight Back to Previous" — cross-module note:** ✅ **Resolved.** Full spec lives in Annotation System §3.3. Pairing is deterministic (nearest prior in reading order, same chapter only). Cross-chapter highlights not supported — error message directs user to create two separate highlights.
- **Bracket bookmark persistence:** currently transient (cleared on close). Should an in-progress bracket survive app backgrounding and a return to the book? Probably yes — clear on close, but survive background/foreground. To be confirmed during implementation.
- **Codex-to-Codex direct transfer:** MultipeerConnectivity for direct device-to-device epub transfer without Wi-Fi network. Deferred to v1.1.

---

*Module status: Directive substantially revised — Wi-Fi transfer dropped (redundant with iCloud Drive), PDF export dropped, bracket bookmark system added, rich text formatting engine specified, text sharing and annotation export unified under one engine.*  
*Last updated: April 2026*
