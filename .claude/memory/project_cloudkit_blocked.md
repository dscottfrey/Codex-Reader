---
name: CloudKit work blocked on developer credentials
description: Scott does not yet have a paid Apple Developer account, so CloudKit entitlements cannot be provisioned. Defer all Module 4 (Sync Engine) work that requires a CloudKit container until credentials are in place.
type: project
originSessionId: f8f66f7f-a29c-49b4-97f6-900611c81323
---
CloudKit work is blocked: Scott does not have paid Apple Developer Program credentials yet. CloudKit container identifiers cannot be added to entitlements without a paid team, so SwiftData CloudKit sync, the iCloud container in Module 2 ingestion, and anything else that needs a `iCloud.*` container ID is on hold.

**Why:** CloudKit container provisioning is gated behind the paid Apple Developer Program ($99/yr). Free personal teams in Xcode can sign apps for sideload but cannot create CloudKit containers or push notifications entitlements.

**How to apply:**
- Do not propose Module 4 (Sync Engine) work as the next step, even though `HANDOFF.md` §3 lists it third in priority order. Treat Module 4 as deferred.
- Do not propose adding `iCloud.com.codex.*` container identifiers to entitlements files.
- The iCloud Drive Inbox path in Module 2 (Ingestion) is *also* blocked from end-to-end testing for the same reason — local file paths still work for development; the iCloud Drive container can't be configured yet.
- When suggesting the next priority, prefer: Rendering polish (§2.2 half-size renderer, §2.1.F cross-chapter drag) → document picker / share-sheet intake → Settings screen architecture (§10) → first-launch onboarding (§11). Hold CloudKit until Scott confirms he's enrolled.
- If a piece of work *can* be built now in a way that's CloudKit-ready (e.g., SwiftData models that will later sync), that's fine — just don't flip the `isStoredInMemoryOnly` flag or wire entitlements until the account exists.
