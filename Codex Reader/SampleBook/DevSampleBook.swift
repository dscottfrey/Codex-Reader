//
//  DevSampleBook.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A development-only shortcut that hands the reader a real (SwiftData-
//  backed) `Book` pointing at one of the bundled sample epubs. Lets us
//  exercise the Rendering Engine end-to-end without going through the
//  Ingestion Pipeline (file picker, DRM check, dedupe, copy-to-library,
//  SwiftData insert).
//
//  WHY IT'S GATED BY #if DEBUG:
//  Shipping a "Load Sample" button in a release build would be a bad
//  smell — production users shouldn't have debug affordances visible
//  at all. The whole file compiles out of Release builds; even the
//  bundled epubs are only looked up from Debug code paths.
//
//  WHY THE Book IS NOW INSERTED INTO SwiftData (changed 2026-05-01):
//  Earlier versions of this file built a *transient* Book that wasn't
//  inserted into any context — so the reader's debounced position
//  saves (`book.lastChapterHref` / `book.lastScrollOffset`) silently
//  went nowhere, and reopening the same sample landed on page 1.
//  Scott wanted reopen-to-last-position to work for the dev cycle, so
//  the sample Book is now a real SwiftData @Model record. Each sample
//  has a stable UUID derived from its slug, so subsequent
//  `materialise(_:in:)` calls fetch the existing record (preserving
//  position) instead of inserting a duplicate.
//
//  WHY SAMPLES SHOW UP IN THE LIBRARY ALONGSIDE REAL BOOKS:
//  Because they are real Books, the bookshelf and list views — which
//  back onto a plain `@Query<Book>` — render them automatically. This
//  is intentional: Scott uses the three samples as the initial
//  library while iterating on rendering / library UI, and there are
//  no real ingested books to be confused with. The whole insertion
//  path is `#if DEBUG`-gated so a Release build never persists them.
//
//  WHERE THE FILES LIVE:
//  `Codex Reader/SampleBook/<slug>.epub` — inside the app target's
//  source directory so Xcode's filesystem-synchronized group bundles
//  them as resources automatically. The repo-root `Samples/` folder
//  is the "source" (a place Scott can drop fresh epubs for testing);
//  the copies in this folder are what the binary actually sees.
//

import Foundation
import SwiftData

#if DEBUG

enum DevSampleBook {

    /// Description of one bundled sample epub. The `slug` is both the
    /// resource basename inside the bundle and the key UserDefaults
    /// uses to remember which sample was opened last. The derived `id`
    /// is a deterministic UUID — same slug in, same UUID out, every
    /// launch — so SwiftData can fetch the existing record across
    /// launches without random-UUID drift.
    struct Sample: Identifiable, Hashable {
        let slug: String
        let title: String
        let author: String
        let language: String

        /// Stable UUID derived from the slug. See `uuid(for:)` below.
        var id: UUID { Self.uuid(for: slug) }

        /// Resolve the bundled epub URL for this sample. Returns nil if
        /// the resource is missing from the bundle (build problem —
        /// the menu items will simply fail to open).
        var bundleURL: URL? {
            Bundle.main.url(forResource: slug, withExtension: "epub")
        }

        // MARK: - Stable-UUID derivation

        /// Fold an ASCII slug into a fixed UUID. The first 16 bytes of
        /// the slug (zero-padded) become the UUID's bytes — same string
        /// in, same UUID out, no hashing library needed. A collision
        /// would require two different slugs sharing their first 16
        /// characters byte-for-byte; our slugs are short and distinct
        /// so a clash isn't realistic, and an unlikely future clash
        /// would just mean two samples sharing one record (annoying
        /// but not a data-loss bug). Picked over `UUID()` because we
        /// need cross-launch stability — random UUIDs would create a
        /// brand-new record every cold launch and reading position
        /// would never persist.
        private static func uuid(for slug: String) -> UUID {
            var bytes = [UInt8](repeating: 0, count: 16)
            for (i, b) in slug.utf8.prefix(16).enumerated() {
                bytes[i] = b
            }
            let t: uuid_t = (
                bytes[0],  bytes[1],  bytes[2],  bytes[3],
                bytes[4],  bytes[5],  bytes[6],  bytes[7],
                bytes[8],  bytes[9],  bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
            return UUID(uuid: t)
        }
    }

    // MARK: - Catalog

    /// The three sample epubs Scott has loaded into the project for
    /// dev-cycle testing. Order here is the order they appear in the
    /// dev-only Menus; the first entry is also the fallback for
    /// "no last-opened sample on record" (first cold launch).
    static let all: [Sample] = [
        Sample(
            slug: "the-secret-garden",
            title: "The Secret Garden",
            author: "Frances Hodgson Burnett",
            language: "en"
        ),
        Sample(
            slug: "darksight-dare",
            title: "Darksight Dare",
            author: "Lois McMaster Bujold",
            language: "en"
        ),
        Sample(
            slug: "dragonwriter",
            title: "Dragonwriter: A Tribute to Anne McCaffrey",
            author: "Todd McCaffrey",
            language: "en"
        ),
    ]

    // MARK: - "Last opened" preference

    /// UserDefaults key for the slug of the most-recently-opened sample.
    /// Read by `ContentView`'s auto-open block on cold launch.
    private static let lastOpenedDefaultsKey = "dev.lastOpenedSampleSlug"

    /// The slug of the sample most recently opened via a dev affordance,
    /// or nil on first launch.
    static var lastOpenedSlug: String? {
        UserDefaults.standard.string(forKey: lastOpenedDefaultsKey)
    }

    /// The Sample record corresponding to `lastOpenedSlug`, falling back
    /// to `all.first` if the slug isn't recognised (e.g. samples were
    /// renamed since the last run) or has never been set.
    static var lastOpenedOrDefault: Sample {
        if let slug = lastOpenedSlug,
           let s = all.first(where: { $0.slug == slug }) {
            return s
        }
        return all[0]
    }

    /// Remember which sample was just opened so the next cold launch
    /// reopens the same one. Call this from each Menu item / auto-open
    /// site immediately before invoking `onOpenBook`.
    static func rememberLastOpened(_ sample: Sample) {
        UserDefaults.standard.set(sample.slug, forKey: lastOpenedDefaultsKey)
    }

    // MARK: - Materialisation

    /// Materialise every sample at once so all three appear in the
    /// library list, not just the one being auto-opened. Called from
    /// `ContentView`'s cold-launch task. Does the cover-extraction work
    /// up front for any sample that doesn't have one cached yet — about
    /// half a second on first install for the three bundled epubs,
    /// nothing on subsequent launches.
    @MainActor
    static func materialiseAll(in context: ModelContext) {
        for sample in all {
            _ = materialise(sample, in: context)
        }
    }


    /// Fetch the SwiftData `Book` for this sample, inserting a new
    /// record if one doesn't exist yet. Returns nil only if the bundled
    /// epub is missing — every other state is recoverable.
    ///
    /// `localFallbackPath` is refreshed to the current bundle URL on
    /// every call, because the simulator's app sandbox path can change
    /// between runs; the position fields (`lastChapterHref`,
    /// `lastScrollOffset`) are left untouched so reopen-to-last-position
    /// keeps working.
    @MainActor
    static func materialise(_ sample: Sample, in context: ModelContext) -> Book? {
        guard let url = sample.bundleURL else { return nil }

        // Look up an existing record by stable id. If we already
        // materialised this sample on a prior launch, we want the same
        // Book back so its lastChapterHref / lastScrollOffset persist.
        let targetID = sample.id
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            // Refresh the file path in case the sandbox moved between
            // runs (common in the simulator). Don't touch reading state.
            existing.localFallbackPath = url.path
            ensureCover(for: existing, sampleURL: url)
            return existing
        }

        // First time we've seen this sample on this device — insert a
        // fresh record. Storage is .localOnly per the project's
        // local-first storage decision; iCloud Drive is a future opt-in.
        let book = Book(
            id: sample.id,
            title: sample.title,
            author: sample.author
        )
        book.language = sample.language
        book.storageLocation = .localOnly
        book.localFallbackPath = url.path
        book.typographyMode = .userDefaults
        context.insert(book)
        ensureCover(for: book, sampleURL: url)
        return book
    }

    /// Make sure the sample's `Book` has a cover image cached on disk.
    /// Skips the work if the cached file already exists; otherwise runs
    /// the same `EpubParser` + `CoverExtractor` pair that real ingestion
    /// uses, falling through to a generated placeholder when parsing
    /// fails. Runs synchronously on the calling thread — for the three
    /// small bundled samples this is a few tens of milliseconds at most,
    /// and only happens on first materialisation per device. If launch
    /// hitch becomes visible, move this to a background Task.
    @MainActor
    private static func ensureCover(for book: Book, sampleURL: URL) {
        // Skip if we already have a cover file on disk. The path is
        // re-checked on every materialise because Application Support
        // can be wiped (simulator reset, App Cleanup) leaving the
        // Book.coverCachePath pointing at nothing.
        if let path = book.coverCachePath,
           FileManager.default.fileExists(atPath: path) {
            return
        }
        let parsed = try? EpubParser.parse(sampleURL)
        let path = CoverExtractor.extractCover(
            forBookID: book.id,
            title: book.title,
            author: book.author,
            from: parsed
        )
        book.coverCachePath = path
    }
}

#endif
