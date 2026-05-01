//
//  PageImageCache.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A bounded LRU cache of pre-rendered page UIImages, keyed by
//  (chapterHref, pageIndex). Owned by `ReaderViewModel`; consumed by
//  `PaginatedChapterView` when it needs the image for a given page.
//
//  WHY A BOUNDED LRU:
//  Each page UIImage at iPad-Retina resolution is roughly 30 MB.
//  Holding every page of every chapter in memory would blow the heap
//  on long books. A small bounded cache (default 6 — see capacity
//  rationale below) keeps the working set tiny while still holding the
//  pages adjacent to the user's current position, which is what 99% of
//  page turns reach for.
//
//  WHY 6 (DEFAULT CAPACITY):
//  iPad-landscape Page Curl renders an open-book spread of two pages
//  side-by-side. The user's natural sequential motion is current
//  spread → next spread → previous spread. That covers 6 page slots
//  (3 spreads × 2 pages each). For single-page modes (iPhone, iPad
//  portrait, Slide) 3 slots cover the same range; the extra 3 slots
//  are spent on cross-chapter pre-render entries (the next chapter's
//  first page or first spread) which is a more valuable use of the
//  budget than caching deeper into the current chapter — nobody pages
//  10 ahead sequentially, so caching for that case is wasted memory.
//  See Rendering directive §3.3 and the discussion preceding the
//  Milestone-A commit for the full rationale.
//
//  WHY HAND-ROLLED, NOT NSCache:
//  NSCache is non-deterministic about eviction (system-driven) and
//  doesn't expose enumeration. We need to:
//    - guarantee evict order (oldest-touched first, not whatever the
//      OS decides)
//    - invalidate all entries for a single chapter en masse on a
//      typography or viewport change (NSCache can't do this without
//      tracking keys externally)
//  A small `[Key: UIImage]` plus an `[Key]` insertion-order array does
//  both with no surprises.
//

import Foundation
import UIKit

/// Bounded LRU cache of pre-rendered page images.
@MainActor
final class PageImageCache {

    /// Cache key: chapter href + 1-based page index. The chapter href
    /// is the same string `ParsedEpub.SpineItem.href` carries — the
    /// canonical identifier used everywhere else in the reader.
    struct Key: Hashable {
        let chapterHref: String
        let pageIndex: Int   // 1-based, matches PaginationJS convention
    }

    /// Maximum number of UIImages held at once. Eviction is LRU
    /// (least-recently-touched first).
    let capacity: Int

    private var entries: [Key: UIImage] = [:]

    /// Touch order — oldest at index 0, most recently accessed at end.
    /// Manipulated on every `image(...)` lookup and every `setImage(...)`.
    private var touchOrder: [Key] = []

    init(capacity: Int = 6) {
        self.capacity = max(1, capacity)
    }

    /// Look up the cached image for a page. Returns nil on miss.
    /// On a hit, updates the touch order so this entry is the most
    /// recent — meaning a fresh setImage won't evict it.
    func image(forChapter chapterHref: String, page pageIndex: Int) -> UIImage? {
        let key = Key(chapterHref: chapterHref, pageIndex: pageIndex)
        guard let image = entries[key] else { return nil }
        touch(key)
        return image
    }

    /// Store an image for a page. If the cache is at capacity and this
    /// is a new key, the least-recently-touched entry is evicted.
    func setImage(_ image: UIImage, forChapter chapterHref: String, page pageIndex: Int) {
        let key = Key(chapterHref: chapterHref, pageIndex: pageIndex)
        entries[key] = image
        touch(key)
        evictIfNeeded()
    }

    /// Drop every entry belonging to one chapter. Called when the user
    /// changes typography (entire chapter must re-render) or when
    /// viewport size changes (column geometry differs, all snapshots
    /// are stale).
    func invalidate(chapterHref: String) {
        entries = entries.filter { $0.key.chapterHref != chapterHref }
        touchOrder.removeAll { $0.chapterHref == chapterHref }
    }

    /// Drop everything. Called on book close and on app-level events
    /// like memory warnings.
    func clear() {
        entries.removeAll(keepingCapacity: false)
        touchOrder.removeAll(keepingCapacity: false)
    }

    /// Number of currently-cached images. Diagnostic; production code
    /// should not branch on this.
    var count: Int { entries.count }

    // MARK: - Internals

    private func touch(_ key: Key) {
        touchOrder.removeAll { $0 == key }
        touchOrder.append(key)
    }

    private func evictIfNeeded() {
        while touchOrder.count > capacity {
            let oldest = touchOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
