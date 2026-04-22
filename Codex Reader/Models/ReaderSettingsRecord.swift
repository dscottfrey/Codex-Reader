//
//  ReaderSettingsRecord.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A SwiftData wrapper around the user's global `ReaderSettings`. Lives
//  here because it's a pure persistence concern — the meaningful struct is
//  in `ReaderSettings.swift`.
//
//  WHY THE WRAPPER EXISTS:
//  `ReaderSettings` is a Codable value type — perfect for the portable
//  JSON export and per-book overrides, but SwiftData wants a `@Model`
//  class to sync via CloudKit. This file is the bridge: a singleton-style
//  @Model with one field (the JSON blob) so settings sync automatically
//  along with the rest of the SwiftData store.
//
//  WHY ONLY ONE RECORD:
//  Per the Sync Engine directive §4.4, there is one ReaderSettings per
//  user. The `current(in:)` helper returns the only existing record or
//  creates one with defaults if none exists yet.
//

import Foundation
import SwiftData

/// SwiftData record holding the user's global ReaderSettings as a JSON
/// blob. There is only ever one of these records per user (per CloudKit
/// account, since CloudKit private database is per-account).
@Model
final class ReaderSettingsRecord {

    /// JSON-encoded `ReaderSettings`. Stored as data so adding a new
    /// settings field doesn't require a SwiftData migration.
    var settingsData: Data = Data()

    /// Last write time for last-write-wins conflict resolution at the
    /// CloudKit layer (Sync Engine directive §6.4).
    var lastUpdated: Date = Date()

    init(settings: ReaderSettings = .default) {
        self.settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
        self.lastUpdated = Date()
    }

    /// Decode and return the wrapped `ReaderSettings`. Falls back to
    /// `.default` if the blob is missing or corrupt — better to give the
    /// user the shipped defaults than crash on a decode error.
    var settings: ReaderSettings {
        get {
            (try? JSONDecoder().decode(ReaderSettings.self, from: settingsData)) ?? .default
        }
        set {
            settingsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            lastUpdated = Date()
        }
    }

    // MARK: - Singleton accessor

    /// Return the one-and-only ReaderSettingsRecord in this model context,
    /// creating it with shipped defaults if it doesn't exist yet.
    ///
    /// Callers (settings UI, the renderer's CSS builder) should use this
    /// rather than constructing a record directly, so we don't accidentally
    /// end up with two records and a sync conflict over which is canonical.
    @MainActor
    static func current(in context: ModelContext) -> ReaderSettingsRecord {
        let descriptor = FetchDescriptor<ReaderSettingsRecord>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = ReaderSettingsRecord()
        context.insert(fresh)
        return fresh
    }
}
