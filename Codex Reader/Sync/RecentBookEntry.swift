//
//  RecentBookEntry.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  One entry in the recently-active books stack — the cross-device list
//  of "what was I reading on which device, and where." Defined in
//  Module 4 (Sync Engine) §7.1.
//
//  WHY @Model:
//  The stack is synced via CloudKit so every device sees the same
//  order. SwiftData's CloudKit-backed container syncs these
//  automatically.
//
//  WHY THERE'S A FOREIGN-KEY-STYLE bookID INSTEAD OF A RELATIONSHIP:
//  The recently-active record can outlive its book — if the user
//  removes the book from the library, the recent-stack entry should
//  fade naturally rather than crash on a dangling pointer. Storing
//  the bookID as a UUID lets the consumer fetch-or-skip safely.
//

import Foundation
import SwiftData

@Model
final class RecentBookEntry {

    @Attribute(.unique) var id: UUID = UUID()

    /// The book this entry refers to. May resolve to nil if the book
    /// has been deleted since.
    var bookID: UUID = UUID()

    /// Cached title — used so the quick-switch UI can render an entry
    /// even if the Book record can't be fetched (race during a CloudKit
    /// sync, for example).
    var titleSnapshot: String = ""

    /// Name of the device that last touched this book. Used for the
    /// Follow Me / Stay Here logic in §7.2.
    var deviceName: String = ""

    /// The reading position when the book was last closed on the
    /// recording device. Stored here so an alternate device can resume
    /// instantly without waiting on the Book record's sync to land.
    var chapterHref: String = ""
    var scrollOffset: Double = 0.0

    /// When this entry was last updated. Stack ordering is most-recent
    /// first by this timestamp.
    var lastUpdated: Date = Date()

    init(bookID: UUID = UUID(),
         titleSnapshot: String = "",
         deviceName: String = "",
         chapterHref: String = "",
         scrollOffset: Double = 0.0) {
        self.bookID = bookID
        self.titleSnapshot = titleSnapshot
        self.deviceName = deviceName
        self.chapterHref = chapterHref
        self.scrollOffset = scrollOffset
        self.lastUpdated = Date()
    }
}
