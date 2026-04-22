//
//  BookSource.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A user-configured OPDS source (Calibre-Web, COPS, Standard Ebooks…).
//  Defined in Module 2 (Ingestion Engine) §2.2.
//
//  WHY @Model:
//  Sources are user data — the user's named list of servers, including
//  which is the primary for integrated library search. CloudKit sync
//  means an OPDS source added on iPhone shows up on iPad without manual
//  re-configuration.
//
//  WHY CREDENTIALS ARE NOT IN THE @Model:
//  The directive (§2.2) is explicit: credentials are stored in the iOS
//  Keychain, never in plain text. The username/password live in
//  KeychainHelper (Settings module) keyed off the source's id; this
//  record carries only metadata and a `requiresAuth` flag.
//

import Foundation
import SwiftData

@Model
final class BookSource {

    @Attribute(.unique) var id: UUID = UUID()

    /// Friendly name shown in Settings and the Sources tab.
    var name: String = ""

    /// The OPDS feed root URL. Stored as a String because SwiftData +
    /// CloudKit prefer simple types; convert to URL where used.
    var feedURLString: String = ""

    /// True when the source needs Basic Auth. The actual credentials
    /// live in the Keychain keyed off `id.uuidString`.
    var requiresAuth: Bool = false

    /// True for the source that should be queried by integrated library
    /// search (Library Manager §8.4). At most one source has this set.
    var isPrimary: Bool = false

    /// True for sources Codex shipped with (Standard Ebooks, Project
    /// Gutenberg). Used so we don't trample user-edited copies of the
    /// preconfigured sources during a future "reset to defaults" path.
    var isPreconfigured: Bool = false

    var dateAdded: Date = Date()

    /// Convenience accessor — returns nil if the URL is malformed (a
    /// rare case but better than force-unwrapping at every call site).
    var feedURL: URL? { URL(string: feedURLString) }

    init(name: String = "",
         feedURLString: String = "",
         requiresAuth: Bool = false,
         isPrimary: Bool = false,
         isPreconfigured: Bool = false) {
        self.name = name
        self.feedURLString = feedURLString
        self.requiresAuth = requiresAuth
        self.isPrimary = isPrimary
        self.isPreconfigured = isPreconfigured
    }

    // MARK: - Pre-configured defaults

    /// The two sources Codex ships with per directive §2.2 — Standard
    /// Ebooks and Project Gutenberg. The first-launch path inserts these
    /// if no sources exist yet. The user can delete them.
    static func preconfiguredDefaults() -> [BookSource] {
        [
            BookSource(
                name: "Standard Ebooks",
                feedURLString: "https://standardebooks.org/feeds/opds",
                isPreconfigured: true
            ),
            BookSource(
                name: "Project Gutenberg",
                feedURLString: "https://m.gutenberg.org/ebooks/search.opds/",
                isPreconfigured: true
            )
        ]
    }
}
