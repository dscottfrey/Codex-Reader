//
//  DevSampleBook.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A development-only shortcut that hands the reader a ready-to-open
//  `Book` pointing at the bundled copy of *The Secret Garden*. Lets us
//  exercise the Rendering Engine end-to-end without going through the
//  Ingestion Pipeline (file picker, DRM check, dedupe, copy-to-library,
//  SwiftData insert).
//
//  WHY IT'S GATED BY #if DEBUG:
//  Shipping a "Load Sample" button in a release build would be a bad
//  smell — production users shouldn't have debug affordances visible
//  at all. The whole file compiles out of Release builds; even the
//  bundled epub is only looked up from Debug code paths.
//
//  WHY THE Book ISN'T INSERTED INTO SwiftData:
//  We want the sample flow to be non-destructive — opening the sample
//  shouldn't create a permanent entry in the user's library. The
//  ReaderView model reads/writes `book.lastChapterHref` etc. on this
//  transient Book; those writes silently go nowhere because nothing is
//  tracking changes, which is exactly what we want for a dev shortcut.
//
//  WHERE THE FILE LIVES:
//  `Codex Reader/SampleBook/the-secret-garden.epub` — inside the app
//  target's source directory so Xcode's filesystem-synchronized group
//  bundles it as a resource automatically. The repo-root `Samples/`
//  folder is the "source" (a place Scott can drop fresh epubs for
//  testing); this copy is the one the binary actually sees.
//

import Foundation

#if DEBUG

enum DevSampleBook {

    /// Filename inside the app bundle. Must match the file the Xcode
    /// synchronised group picks up from `Codex Reader/SampleBook/`.
    private static let resourceName = "the-secret-garden"
    private static let resourceExtension = "epub"

    /// Resolve the bundled epub URL. Returns nil if the resource
    /// wasn't found — the caller shows an informative error rather
    /// than silently crashing.
    static func bundledURL() -> URL? {
        Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        )
    }

    /// Build a transient Book pointing at the bundled epub. Not
    /// inserted into any SwiftData context — see file header.
    ///
    /// Returns nil if the resource is missing from the bundle.
    static func makeBook() -> Book? {
        guard let url = bundledURL() else { return nil }
        let book = Book(
            title: "The Secret Garden",
            author: "Frances Hodgson Burnett"
        )
        // Storage + path wire-up matches what IngestionPipeline would
        // do for a local-only book, so ReaderViewModel.currentEpubURL()
        // resolves correctly.
        book.storageLocation = .localOnly
        book.localFallbackPath = url.path
        book.language = "en"
        book.typographyMode = .userDefaults
        return book
    }
}

#endif
