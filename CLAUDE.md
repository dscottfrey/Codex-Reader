# Codex — iOS/iPadOS epub Reader

## Read This First

Before writing any code or making any decisions, read:

**`Docs/00_OVERALL_DIRECTIVE.md`** — vision, goals, anti-goals, technical stack, development philosophy, settings architecture, and onboarding spec. The coding rules in §6 of that file are not aspirational — they are requirements that apply to every line of code in this project.

**`Docs/HANDOFF.md`** — current build state, known regressions, outstanding work inventoried by module, and the key architectural decisions. This is where the cross-session state lives.

Before working on any specific module, read its directive file. The directive is the spec. Do not implement anything not covered in the directive without flagging it to the project owner first.

## Machine Setup (first session after cloning)

This project is directed across two machines (desktop + laptop). Memory files — decisions, preferences, project context that the assistant has learned — live in this repo at `.claude/memory/` rather than per-machine, so both machines see the same context.

If you are an assistant session on a freshly-cloned repo and the `~/.claude/projects/<project-key>/memory/` directory is empty or missing, the **first** thing to do is run:

```sh
./scripts/link-claude-memory.sh
```

That script symlinks this machine's Claude Code memory directory to `.claude/memory/` in the repo. After that, memory operations in the current session will read and write the in-repo files, and any changes flow to the other machine via `git pull` / `git push` like the rest of the codebase.

If the symlink is already in place from a previous session, the script is a safe no-op — it detects and replaces an existing symlink, and backs up any real directory it finds.

---

## Module Directives

| File | Module | Status |
|---|---|---|
| `Docs/01_RENDERING_ENGINE.md` | Rendering Engine — WKWebView, CSS injection, typography, reader UI | Spec complete |
| `Docs/02_INGESTION_ENGINE.md` | Ingestion Engine — OPDS, iCloud inbox, ingestion pipeline, DRM detection | Spec complete |
| `Docs/03_LIBRARY_MANAGER.md` | Library Manager — bookshelf UI, collections, sync states, search | Spec complete |
| `Docs/04_SYNC_ENGINE.md` | Sync Engine — CloudKit, sidecar files, portable export, "Finished?" logic | Spec complete |
| `Docs/05_SHARE_TRANSFER.md` | Share & Transfer — epub sharing, text formatting engine, annotation export | Spec complete |
| `Docs/06_ANNOTATION_SYSTEM.md` | Annotation System — highlights, notes, bookmarks, "Highlight Back to Previous" | Spec complete |

---

## Project Context

**What this is:** A clean, reliable epub reader for iPhone and iPad. A direct replacement for Apple Books. No DRM, no store, no gamification. Reads books beautifully and reliably.

**Platform:** iOS 17+ and iPadOS 17+  
**Primary framework:** SwiftUI (UIKit bridged where rendering precision requires it)  
**Rendering:** WKWebView  
**Persistence:** SwiftData  
**Sync:** CloudKit (private database, via SwiftData ModelContainer)  
**External dependencies:** None. Keep it that way unless there is a compelling reason.

**Development model:** AI-assisted, directed by a non-developer owner (Scott). This means comments are not optional — they are how the owner reads and understands the code. See §6.2 of the overall directive.

**Current status:** Planning complete. No code written yet.

---

## The Four Rules That Matter Most

These are in the overall directive in full — here as a quick reminder for every session:

1. **Simplest solution that works.** If Apple's SDK does it, use it. If a problem can be solved simply or cleverly, solve it simply. (§6.1)

2. **Comments are part of the deliverable.** Every file gets a header comment. Every function gets a plain-English explanation. When a working solution was reached after several attempts, the final comment must explain what was tried, what failed, and *why* the working approach works — not just what it does. Stale comments that no longer match the code are deleted, never left in place. (§6.2)

3. **One file, one job.** No file over ~200 lines. Views don't contain business logic. Models don't contain UI. (§6.3)

4. **Work with Apple, not against it.** If an approach requires fighting UIKit or SwiftUI in a non-trivial way, stop and flag it before writing the code. (§6.5)

---

## How to Work With Scott

- When starting a new module or feature: read the directive for that module, then summarise what you're going to build and in what order before writing any code. Give Scott a chance to redirect before work begins.
- When a directive has an open question that needs resolving to proceed: surface it explicitly. Don't pick an answer silently.
- When something in the directive is ambiguous or incomplete: say so. Don't guess.
- When a proposed approach would require fighting the framework: flag it using the exact language in §6.5 of the overall directive. Scott decides whether to proceed.
- When a working solution was reached after iteration: update the comments to reflect the journey, not just the destination. This is regression protection.
- Scott is not a developer. Explanations should be in plain English. Code comments should be legible to a careful non-developer reader.
