//
//  PageRenderNotifications.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Notification.Name and userInfo keys used to broadcast page-
//  render events from `ReaderViewModel.renderCurrentChapter` to any
//  live `PageImageVC` that needs to know its image just landed in
//  the cache.
//
//  WHY NotificationCenter (NOT A CLOSURE OR Observable):
//  The set of live PageImageVCs is owned by UIPageViewController and
//  not directly exposed to ReaderViewModel. Observers come and go as
//  UIKit caches/discards page VCs around the user's current position.
//  NotificationCenter is the right pattern for a fanout where the
//  publisher doesn't know the receivers — it's exactly the use case
//  Apple's docs cite for it. Closures would require maintaining a
//  registry of every live VC; @Observable would force every VC to be
//  a SwiftUI view (they aren't, they're UIViewControllers).
//

import Foundation

extension Notification.Name {
    /// Posted by `ReaderViewModel` after a page UIImage lands in
    /// `PageImageCache`. The `userInfo` dictionary carries the
    /// chapter href and 1-based page index — see
    /// `CodexNotificationKey`.
    static let codexPageRendered = Notification.Name("codex.pageRendered")
}

enum CodexNotificationKey {
    /// String — `ParsedEpub.SpineItem.href` of the chapter the
    /// rendered page belongs to.
    static let chapterHref = "chapterHref"

    /// Int — 1-based page index within the chapter.
    static let pageIndex = "pageIndex"
}
