//
//  ICloudInboxMonitor.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Watches `iCloud Drive/Codex/Inbox/` for new epub files. Defined in
//  Module 2 (Ingestion Engine) §3.
//
//  WHY NSMetadataQuery:
//  NSMetadataQuery is Apple's documented API for observing iCloud Drive
//  changes from the foreground. It delivers a notification when files
//  appear in the watched scope without us polling. Polling iCloud Drive
//  is unreliable — files can take seconds to materialise after upload —
//  so we let the framework tell us when to look.
//
//  WHAT'S NOT YET HOOKED UP:
//  - The actual iCloud container URL must be discovered via
//    `FileManager.url(forUbiquityContainerIdentifier:)`. The iCloud
//    container identifier needs to be added to the entitlements file
//    first; see TODO in init().
//  - Background observation (when the app is closed). The directive
//    explicitly says monitoring runs when the app is in the foreground
//    + a check on every launch / foreground transition. That second
//    half is the launch-time scan in `scanInboxOnce()`.
//

import Foundation

/// Watches the Codex iCloud Inbox and forwards every new epub to the
/// ingestion pipeline.
@MainActor
final class ICloudInboxMonitor {

    // MARK: - Inputs

    /// Called for each new epub file discovered in the Inbox. The
    /// caller (typically the IngestionPipeline) is responsible for
    /// running the file through the pipeline AND removing it from the
    /// Inbox once successfully ingested (the Inbox is a drop zone, not
    /// a permanent home — directive §3).
    let onNewFile: (URL) -> Void

    // MARK: - Internals

    private let metadataQuery = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []

    init(onNewFile: @escaping (URL) -> Void) {
        self.onNewFile = onNewFile

        // TODO: When the project has an iCloud container identifier
        // configured in the entitlements (com.apple.developer.icloud-
        // container-identifiers in Codex_Reader.entitlements is
        // currently empty), inject it here so we scope the query to
        // Codex's container instead of the generic ubiquity scope.
        metadataQuery.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope
        ]
        metadataQuery.predicate = NSPredicate(format: "%K LIKE '*.epub'", NSMetadataItemFSNameKey)
    }

    /// Begin observing the Inbox folder. Call when the app comes to
    /// the foreground; balance with `stop()` when it backgrounds so we
    /// don't leak the query.
    func start() {
        let center = NotificationCenter.default

        // Initial scan complete + every later update both fire the same
        // handler. NSMetadataQuery batches these for us so we don't get
        // a thousand notifications for a thousand new files — we get one
        // batch and iterate.
        // The notification queue is .main so we hop onto MainActor to
        // call our actor-isolated processCurrentResults — without that
        // hop the compiler warns about cross-actor invocation.
        // Capture self by reference and re-bind inside the Task so
        // Swift 6 strict concurrency is happy. Notifications fire on
        // the main queue so the hop is essentially free.
        let initial = center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.processCurrentResults() }
        }

        let updated = center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadataQuery,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.processCurrentResults() }
        }

        observers = [initial, updated]
        metadataQuery.start()
    }

    /// Stop observing. Removes notification observers and stops the
    /// underlying query.
    func stop() {
        metadataQuery.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// One-shot scan of the Inbox — used at launch to catch any files
    /// that arrived while the app wasn't running. Calls `onNewFile` for
    /// every epub found.
    func scanInboxOnce() {
        guard let inboxURL = inboxDirectory() else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where url.pathExtension.lowercased() == "epub" {
            onNewFile(url)
        }
    }

    // MARK: - Helpers

    /// Walk the current NSMetadataQuery results and emit a callback for
    /// each .epub file inside the Codex Inbox folder. We pause and
    /// re-enable updates around the iteration because reading
    /// `metadataQuery.results` while live updates are firing can
    /// produce inconsistent snapshots.
    private func processCurrentResults() {
        metadataQuery.disableUpdates()
        defer { metadataQuery.enableUpdates() }

        for case let item as NSMetadataItem in metadataQuery.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.pathExtension.lowercased() == "epub",
                  url.path.contains("/Codex/Inbox/")
            else { continue }
            onNewFile(url)
        }
    }

    /// Resolve the URL of the iCloud Drive Codex Inbox. Returns nil if
    /// iCloud is unavailable.
    private func inboxDirectory() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) else { return nil }
        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Codex", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }
}
