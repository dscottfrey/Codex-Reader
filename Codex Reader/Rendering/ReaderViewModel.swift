//
//  ReaderViewModel.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Observable state for the reader. Holds the open book, the current
//  chapter, the open/closed state of the chrome, and the cached effective
//  settings. The ReaderView observes this and rebuilds when it changes.
//
//  WHY A SEPARATE FILE:
//  Per the §6.3 rule "views don't contain business logic", the reader's
//  state and the chapter-loading logic do not live inside ReaderView.swift.
//  ReaderView is presentation only.
//
//  WHAT'S NOT YET HERE:
//  - Pagination calculation. Stubbed; will be its own file once the
//    parser is real and we have actual chapter content to measure.
//  - The ambient brightness watcher for "Match Surroundings" theme mode.
//  - The auto-save timer for reading position. Logged as a TODO below.
//

import Foundation
import SwiftData
import SwiftUI
@preconcurrency import WebKit

@MainActor
@Observable
final class ReaderViewModel {

    // MARK: - Inputs

    /// The book currently being read.
    let book: Book

    /// The user's global settings, captured at open time and refreshed
    /// whenever Settings changes them.
    var globalSettings: ReaderSettings

    // MARK: - State

    /// True while the title/metadata strips (System 1 chrome) are visible.
    /// Toggled by a centre-tap on the reading surface.
    var chromeVisible: Bool = false

    /// True when the floating options panel (System 2) is open. Settings,
    /// TOC, bookmarks, share — see directive §4.1.
    var optionsPanelOpen: Bool = false

    /// True while the reader settings (Aa) bottom sheet is open.
    var settingsPanelOpen: Bool = false

    /// True the very first time this book is opened, when the typography
    /// prompt (§4.6) needs to appear before the first chapter is shown.
    var typographyPromptShown: Bool = false

    /// Currently-loaded chapter href. nil while the parser is still
    /// figuring out where to start.
    var currentChapterHref: String?

    /// The parsed epub — populated once `loadBook()` completes. nil until
    /// then; the view shows a loading state while waiting.
    var parsed: ParsedEpub?

    /// User-visible error, if loading or parsing failed. Drives an error
    /// overlay in ReaderView.
    var loadError: String?

    // MARK: - Init

    init(book: Book, globalSettings: ReaderSettings) {
        self.book = book
        self.globalSettings = globalSettings
    }

    // MARK: - Effective settings & CSS

    /// The settings struct that the renderer should actually use for this
    /// book — global, custom, or nil for publisher mode. Re-read every
    /// time, never cached, so a slider drag updates instantly.
    var effective: ReaderSettings? {
        effectiveSettings(global: globalSettings, book: book)
    }

    /// The theme to inject regardless of mode (publisher mode still gets
    /// the user's chosen background colour).
    var theme: ReaderTheme {
        effectiveTheme(global: globalSettings, book: book)
    }

    /// Build the CSS string for the current state. Called by the renderer
    /// when constructing or updating the user script.
    func currentCSS(publisherSafetyFloorPt: CGFloat = 10) -> String {
        CSSBuilder.build(
            effective: effective,
            theme: theme,
            publisherSafetyFloorPt: publisherSafetyFloorPt
        )
    }

    // MARK: - Lifecycle

    /// Try to parse the epub and pick a starting chapter. Called from
    /// ReaderView's `.task` modifier. On failure, populates `loadError`
    /// so the view can show it.
    func loadBook() async {
        // Resolve the on-disk URL of the epub. Books in iCloud Drive may
        // need a download to be triggered first — that's the iCloud
        // module's job; here we just look up the path the Book record
        // says is current.
        guard let fileURL = currentEpubURL() else {
            loadError = "Couldn't find this book's file."
            return
        }

        do {
            let parsed = try EpubParser.parse(fileURL)
            self.parsed = parsed

            // Pick the chapter to land on:
            //   1. If the book has a saved last position, use that.
            //   2. Otherwise, the first linear spine item.
            let startHref =
                book.lastChapterHref
                ?? parsed.spine.first(where: { $0.linear })?.href
                ?? parsed.spine.first?.href
            self.currentChapterHref = startHref

            // First-open typography prompt (§4.6). Shown only when the
            // book has never been read on this device. lastReadDate is
            // a reasonable proxy for "ever opened before".
            if book.lastReadDate == nil {
                self.typographyPromptShown = true
            }
        } catch EpubParserError.parserNotImplemented {
            // Surfaces the technical-spike TODO in EpubParser.swift to
            // the user as a clear, plain-English message rather than a
            // crash or a silent blank page.
            loadError = "Reading is not available yet — the epub parser is not implemented."
        } catch {
            loadError = "Couldn't open this book: \(error.localizedDescription)"
        }
    }

    /// Resolve the URL on disk for the book's epub file. Honours the
    /// `storageLocation` flag (iCloud Drive vs local-only fallback).
    /// TODO: integrate with the iCloud module to trigger downloads when
    /// the file is cloud-only.
    private func currentEpubURL() -> URL? {
        switch book.storageLocation {
        case .iCloudDrive:
            guard let rel = book.iCloudDrivePath else { return nil }
            // TODO: resolve against the real iCloud Drive container URL
            // returned by FileManager.default.url(forUbiquityContainerIdentifier:).
            return URL(fileURLWithPath: rel)
        case .localOnly:
            guard let rel = book.localFallbackPath else { return nil }
            return URL(fileURLWithPath: rel)
        }
    }

    // MARK: - Chrome interactions

    /// Centre-tap on the reading surface — toggles System 1 chrome.
    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            chromeVisible.toggle()
        }
    }
}
