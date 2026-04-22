---
name: Reader chrome — one tap reveals everything
description: Codex Reader — Scott has resolved the Rendering §4.1 "Chrome System 2 invocation" open question. A single tap on the reading surface reveals the title strip, the metadata strip, AND the action icons (close, Aa/settings, and eventually TOC/share/bookmarks).
type: project
originSessionId: b89b30db-30e8-4c38-bf72-44d09a12be26
---
Rendering directive §4.1 describes two chrome systems — "System 1" (title + metadata, tap-toggled) and "System 2" (floating options panel for TOC/settings/share/etc., invocation TBD). The directive listed five candidate invocation mechanisms for System 2 and left it as an open question.

**Decision (2026-04-22, Scott):** collapse the two systems. The same centre-tap that reveals the title and metadata strips also reveals the action icons (close, Aa/settings, and whatever else lives in System 2). There is **no** persistent always-on icon for System 2 and **no** separate gesture.

**How to apply:**
- When implementing new reader-chrome actions (TOC, share, bookmarks-review, full-screen, book-details), add them to the same tap-toggled chrome surface — typically as icons in a top action bar next to the title, or a small icon row just above the bottom metadata strip. Do not add a floating panel with its own invocation.
- Close-book also lives here (new — the directive didn't originally have a close-book affordance).
- The per-page bookmark ribbon in the corner stays persistent regardless — it's a single-tap passive affordance that lives outside the chrome system.
- Don't implement any of the alternative candidates from the §4.1 table (swipe-from-edge, persistent-icon, long-press-on-title-strip, two-finger tap, swipe-up-from-bottom). They're ruled out.

**Why it's right for Codex:** one tap, one gesture, one revelation — matches the simplicity goal (§6.1) and is the pattern seasoned reader users already have muscle memory for. Avoids a second discovery problem for System 2.
