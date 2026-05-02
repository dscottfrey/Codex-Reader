---
name: Local-first storage; iCloud Drive opt-in later
description: Books and library data live in the app's local sandbox (Application Support) by default. iCloud Drive is a future opt-in mode behind a Settings toggle that's greyed-out until Scott has a paid Apple Developer account.
type: project
originSessionId: f8f66f7f-a29c-49b4-97f6-900611c81323
---
Codex's storage strategy is **local-first now, iCloud Drive later**:

- **Epub files** are copied into `Application Support/Codex/Library/` (the app's local sandbox). This needs no entitlements and works on every device, including ones without iCloud.
- **Library metadata, annotations, reading position** live in a local SwiftData store with `isStoredInMemoryOnly: false` but no CloudKit container configured.
- **Sidecar `.codex` files** (if/when implemented) write to local Documents.
- **iCloud Drive integration is deferred** until Scott has a paid Apple Developer account and can provision an `iCloud.*` container. When it lands, it shows up as a Settings toggle ("Use iCloud Drive for book files") that migrates files from local sandbox to the iCloud Drive container.
- **CloudKit sync** (Module 4 — library/annotation sync across devices) is also deferred per `project_cloudkit_blocked.md`. Independent question from iCloud Drive — both are blocked on the same dev-account gate but they don't depend on each other.

**Why:**
- The directive (Overall §2: "Codex never holds a book hostage to iCloud") and Settings §10 already describe local-only mode as a first-class state, not a degraded fallback. So this isn't a workaround — it's the directive's literal stance.
- Scott doesn't have a paid dev account yet, so iCloud entitlements can't be provisioned. Pretending iCloud is the default and Application Support is a fallback (the current ingestion code's stance) generates bugs at the iCloud paths that can't be tested.
- The `Book` model already supports both modes (`iCloudDrivePath`, `localFallbackPath`, `storageLocation` enum) — flipping the default is a small change, not a refactor.

**How to apply:**
- When ingesting books, default to `Book.storageLocation = .localOnly` and write to Application Support. Don't propose paths that touch the iCloud Drive container.
- When designing UI that references storage, treat local-only as the normal state. iCloud-related affordances (sync status, "Force re-upload," etc.) are visible but disabled with an "iCloud not configured" message until the cert arrives.
- When the dev account exists, the migration path is: (a) add `iCloud.*` container to entitlements, (b) un-grey the iCloud toggle in Settings, (c) on toggle-on, copy files from Application Support into the iCloud Drive container and update each `Book.storageLocation` + `iCloudDrivePath`. Plan for this; don't build for it now.
- Per-device file sync (the iPad sees what the iPhone has) is a *consequence* of iCloud Drive, not a separate feature. Don't propose ad-hoc multi-device sync mechanisms in the local-only era — there isn't one, and that's fine.
