//
//  Collection.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A user-curated grouping of books — the same concept the directive
//  calls a "shelf" in the Bookshelf view and a "tag" in bulk-management
//  contexts (Library Manager directive §9.3).
//
//  WHY @Model:
//  Collections are user data. They sync via CloudKit alongside the books
//  they contain. Smart collections (All / Reading / Unread / Finished)
//  are also stored as records so the UI can sort and order them in the
//  sidebar consistently with manual collections.
//
//  WHY bookIDs IS [UUID] AND NOT A SwiftData RELATIONSHIP:
//  Two reasons. (1) The directive (§15) explicitly stores collection
//  membership as `[UUID]`. (2) SwiftData with CloudKit has known
//  limitations around many-to-many relationships; storing the IDs as a
//  simple array sidesteps those.
//

import Foundation
import SwiftData

/// One named collection of books. Manual collections track membership
/// via `bookIDs`; smart collections derive their contents at read time
/// from `smartFilter`.
@Model
final class Collection {

    @Attribute(.unique) var id: UUID = UUID()

    /// Display name shown on the shelf label and in the sidebar.
    var name: String = ""

    /// True for the auto-populated collections (All / Reading / Unread /
    /// Finished). Smart collections have no editable bookIDs — their
    /// contents are derived at query time from `smartFilter`.
    var isSmartCollection: Bool = false

    /// The smart-filter predicate when this is a smart collection. nil
    /// for manual collections.
    var smartFilterRaw: String?

    /// Convenience accessor for the typed smart filter.
    var smartFilter: SmartFilter? {
        get {
            guard let raw = smartFilterRaw else { return nil }
            return SmartFilter(rawValue: raw)
        }
        set { smartFilterRaw = newValue?.rawValue }
    }

    /// Manual collection membership. Empty for smart collections.
    var bookIDs: [UUID] = []

    var dateCreated: Date = Date()

    /// User-defined display order. Lower values appear higher in the
    /// sidebar / earlier in the shelf list.
    var sortOrder: Int = 0

    init(name: String = "",
         isSmartCollection: Bool = false,
         smartFilter: SmartFilter? = nil) {
        self.name = name
        self.isSmartCollection = isSmartCollection
        self.smartFilterRaw = smartFilter?.rawValue
    }
}

/// The set of supported smart-collection filters. Each value maps to a
/// predicate the library queries with.
enum SmartFilter: String, Codable {
    case all
    case reading
    case unread
    case finished
    case unavailable
}
