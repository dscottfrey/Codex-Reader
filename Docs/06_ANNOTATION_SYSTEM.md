# Codex — Module 6: Annotation System Directive

**Module:** Annotation System  
**Priority:** High — essential for serious readers  
**Dependencies:** Rendering Engine (annotations appear within reading view), Sync Engine (annotations synced across devices), Share & Transfer (annotation export)

---

## 1. Purpose

The Annotation System allows readers to interact meaningfully with the text they read. It provides three types of annotations — highlights, notes, and bookmarks — along with a way to review, manage, and export them. The system is designed to be unobtrusive while reading but immediately accessible when needed.

---

## 2. Annotation Types

### 2.1 Highlights

A highlight marks a range of text with a color overlay.

**Colors available:**
- Yellow (default)
- Green
- Blue
- Pink / Rose
- Orange

The user selects text (using the native iOS text selection mechanism via WKWebView), taps "Highlight" in the callout, and optionally selects a color. The default color is the last color the user used.

**Visual appearance in the reader:**
- Highlighted text shows a colored background under the text.
- The highlight must survive page turns (it is stored by character offset, not screen position, and re-applied each time the chapter loads).

### 2.2 Notes

A note attaches a text comment to a range of selected text. Notes may or may not include a highlight — a note with no highlight is valid (it attaches to the text position without coloring it).

**Creating a note:**
1. Select text
2. Tap "Note" in the callout (or tap "Highlight" and then tap the highlight to add a note)
3. A modal text input appears
4. User types their note and taps "Save"

**Visual appearance:**
- Text with a note shows a small note indicator icon in the margin (right or left margin, user-configurable).
- Tapping the indicator opens the note text.

### 2.3 Bookmarks

A bookmark marks a position in the book (the current page/chapter/offset) without selecting text.

**Creating a bookmark:**
- A bookmark ribbon is permanently visible in the corner of the reading page — always present regardless of whether the navigation chrome is showing. It is not part of the tap-toggled chrome.
- Standard mode: top-right corner of the reading area.
- Skeuomorphic mode (page stack edges active): leading edge of the page, near the spine.
- **Outline** = no bookmark at this position. Tap to create one instantly.
- **Solid red** = bookmark exists. Tap to remove it instantly.
- No dialog, no confirmation. A subtle haptic confirms each action.

**Adding a label:** long-press the ribbon → a small inline text field appears directly below the ribbon. Label is optional. Unlabelled bookmarks display the chapter name and reading position in the annotation review screen.

**Visual appearance in the reader:**
- The ribbon itself is the visual indicator — always visible, state communicated by fill (outline vs solid red).
- In the annotation review screen, bookmarks show their label (if set) or chapter + position reference.

---

## 3. Annotation Interaction in the Reader

### 3.1 Text Selection Flow

When the user selects text in the WKWebView, the native iOS callout bar appears. Codex adds its actions at the front without removing any system-provided actions. Full callout bar specification is in the Rendering Engine directive (§4.8). The Annotation System is responsible for the behaviour of the Codex-specific actions:

- **Highlight** — creates a highlight at the selected range using the last-used colour.
- **Note** — opens the note editor (see §2.2). Creates a highlight+note annotation.

All other actions (Copy, Look Up, Search Web, Translate, Share) are standard iOS — preserved and not modified.

**Implementation:** custom actions added via `UIEditMenuInteraction` (iOS 16+). Additive only — no system actions are suppressed.

### 3.2 Tapping an Existing Highlight

When the user taps on an existing highlight, a popover appears with:

- The current note text (if any), or an **"Add note"** prompt
- **Colour picker** — change highlight colour (same five colours)
- **"Edit note"** (if a note exists)
- **"Remove highlight"**
- **"Copy"** — copies the highlighted text to clipboard (plain text)
- **"Share"** — share sheet with highlighted text, formatted via the text formatting engine (rich text + plain text, attribution appended). See Share & Transfer §3.
- **"Highlight Back to Previous"** — see §3.3 below

### 3.3 Highlight Back to Previous

When tapping a highlight and selecting **"Highlight Back to Previous"**, Codex creates a single unified highlight spanning from the start of the nearest prior highlight (in reading order within the same chapter) to the end of the tapped highlight. The two anchor highlights are absorbed into the larger one.

**Use case:** the user highlights a word at the start of a long passage, reads forward, highlights a word at the end, then taps the end highlight and selects "Highlight Back to Previous." Everything between the two anchor words becomes a single highlight.

**Rules:**
- "Highlight Back to Previous" is only available when there is at least one earlier highlight in the same chapter.
- If the nearest prior highlight is in a different chapter, the option does not appear — cross-chapter highlights are not supported (see below).
- If there are multiple prior highlights in the same chapter, the action always connects to the immediately preceding one in reading order. No ambiguity.

**Chapter boundary rule:** highlights are chapter-scoped. If the passage between the two anchors crosses a chapter boundary, "Highlight Back to Previous" is not offered. An informational message explains: *"Highlights can't span chapters. Create a highlight in each chapter separately."* This is a deliberate simplicity constraint — cross-chapter highlight data structures add significant complexity for a rare edge case.

**The resulting highlight** behaves identically to any other highlight. It can be tapped to show the popover, shared, exported, coloured, noted, and deleted in the same ways.

### 3.3 Annotation Rendering

Annotations are stored with:
- Book ID
- Chapter href (which file in the epub spine)
- Start and end character offsets within the chapter's text content

When a chapter loads in WKWebView, the Rendering Engine queries the Annotation System for all annotations in that chapter and injects JavaScript that applies highlight overlays and margin markers at the correct positions.

This must happen after the page is rendered and after the user CSS overrides are applied, to ensure annotations sit on top of the final rendered text.

---

## 4. Annotation Review Screen

Accessible from:
- The reader's options panel → "Bookmarks, Highlights & Notes"
- The book context menu in the library → "View Annotations"

**Layout:**
- A list of all annotations for the current book, in reading order (chapter order, then position within chapter).
- Each row shows:
  - Annotation type icon (highlight / note / bookmark)
  - Highlighted text excerpt (truncated if long)
  - Note text (if any)
  - Chapter name
  - Color swatch (for highlights)
  - Date created
- Tapping a row navigates to that annotation in the reader.
- Swipe left to delete an annotation (with undo).
- A filter control at the top: **All | Highlights | Notes | Bookmarks**
- "Export" button in the navigation bar (see Share & Transfer directive, §3).

---

## 5. Data Model

```swift
struct Annotation: Identifiable, Codable {
    var id: UUID
    var bookID: UUID
    var type: AnnotationType            // .highlight | .note | .bookmark
    var chapterHref: String             // e.g., "OEBPS/chapter03.xhtml"
    var startOffset: Int                // character offset from start of chapter text
    var endOffset: Int                  // character offset (= startOffset for bookmarks)
    var highlightColor: HighlightColor? // .yellow | .green | .blue | .pink | .orange
    var noteText: String?               // optional for highlights, main content for notes
    var bookmarkLabel: String?          // optional label for bookmarks
    var createdAt: Date
    var modifiedAt: Date
    var deletedAt: Date?                // soft delete for sync purposes
}

enum AnnotationType: String, Codable {
    case highlight
    case note
    case bookmark
}

enum HighlightColor: String, Codable {
    case yellow, green, blue, pink, orange
    
    var color: Color {
        switch self {
        case .yellow: return Color.yellow.opacity(0.4)
        case .green: return Color.green.opacity(0.4)
        case .blue: return Color.blue.opacity(0.3)
        case .pink: return Color.pink.opacity(0.3)
        case .orange: return Color.orange.opacity(0.35)
        }
    }
}
```

---

## 6. Sync Integration

All annotations sync via the Sync Engine (CloudKit). See the Sync Engine directive for the CloudKit record schema.

Key sync behaviors:
- Annotations are merged across devices (an annotation added on the iPhone appears on the iPad without overwriting iPad annotations).
- Deleted annotations are soft-deleted (the `deletedAt` field is set); the record remains in CloudKit briefly to propagate the deletion to other devices, then can be purged after 30 days.
- Annotation order is always derived from position in the text (chapter index + character offset), not creation time.

---

## 7. Export (Summary)

Full export specification is in the Share & Transfer directive (§5). Summary:

- Export formats: Rich text (.rtf, default), Plain text (.txt), Markdown (.md)
- PDF export is not offered — dropped as no clear use case
- Triggered from the annotation review screen Export button, the reader options panel, or the book context menu
- Delivered via the iOS system share sheet with the generated file attached

---

## 8. Performance Requirements

- Annotation injection into WKWebView must complete within 100ms of chapter load.
- The annotation review screen must load and be scrollable instantly even for books with hundreds of annotations.
- Annotation creation (tap to highlight) must feel immediate — no visible delay.

---

## 9. Accessibility

- Highlights must have sufficient color contrast for users with color vision deficiency. Consider offering patterns (underline, box) as an alternative to color fills in Settings.
- The note editor must support Dynamic Type and be screen-reader accessible.
- All annotation icons must have accessibility labels.

---

## 10. Open Questions

- **Overlapping highlights:** If a user tries to highlight text that overlaps an existing highlight, what happens? Options: (a) extend the existing highlight, (b) create a second highlight that visually overlaps, (c) ask the user. Recommendation: allow overlapping highlights in v1 (simplest implementation); refine in v1.1.
- **Note-only annotations (no highlight):** Deferred. Not in scope for v1. Revisit in v1.1 if there is demand.
- **Cross-chapter highlights:** ✅ **Decided.** Not supported. Highlights are chapter-scoped. "Highlight Back to Previous" is unavailable when the nearest prior highlight is in a different chapter. An informational message directs the user to create two separate highlights. Use case is too rare to justify the data model complexity.
- **Annotation search:** Search across annotation text (find where you made a specific note). Scope for v1.1.
- **Color customization:** User-defined hex colours for highlights. Nice-to-have, not a v1 requirement.

---

*Module status: Directive revised — bookmark ribbon spec updated, Highlight Back to Previous added (§3.3), chapter boundary rule decided, note-without-highlight deferred, PDF export dropped, access points updated to options panel.*  
*Last updated: April 2026*
