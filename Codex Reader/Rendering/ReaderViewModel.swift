//
//  ReaderViewModel.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The Observable state for the reader. Holds the open book, the
//  current chapter, chrome state, the pagination engine, and the
//  effective settings. The ReaderView observes this and rebuilds
//  when it changes.
//
//  WHY A SEPARATE FILE:
//  Per the §6.3 rule "views don't contain business logic", the
//  reader's state and the chapter-loading / page-turning logic do
//  not live inside ReaderView.swift. ReaderView is presentation only.
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
    var chromeVisible: Bool = false

    /// True when the floating options panel (System 2) is open.
    var optionsPanelOpen: Bool = false

    /// True while the reader settings (Aa) bottom sheet is open.
    var settingsPanelOpen: Bool = false

    /// True the very first time this book is opened, when the typography
    /// prompt (§4.6) needs to appear before the first chapter is shown.
    var typographyPromptShown: Bool = false

    /// Currently-loaded chapter href. nil while the parser is still
    /// figuring out where to start.
    var currentChapterHref: String?

    /// The parsed epub — populated once `loadBook()` completes.
    var parsed: ParsedEpub?

    /// User-visible error, if loading or parsing failed.
    var loadError: String?

    /// Pagination state — reset on chapter change, updated by the
    /// PaginationJS bridge.
    let pagination = PaginationEngine()

    /// When a chapter transition was triggered by a "previous page"
    /// gesture we want to land on the new chapter's last page, not its
    /// first. This flag is read after the chapter finishes loading and
    /// the JS reports its page count, then cleared.
    var pendingJumpToLastPage: Bool = false

    // MARK: - Init

    init(book: Book, globalSettings: ReaderSettings) {
        self.book = book
        self.globalSettings = globalSettings
    }

    // MARK: - Effective settings & CSS

    var effective: ReaderSettings? {
        effectiveSettings(global: globalSettings, book: book)
    }

    var theme: ReaderTheme {
        effectiveTheme(global: globalSettings, book: book)
    }

    func currentCSS(publisherSafetyFloorPt: CGFloat = 10) -> String {
        CSSBuilder.build(
            effective: effective,
            theme: theme,
            publisherSafetyFloorPt: publisherSafetyFloorPt
        )
    }

    /// The effective page-turn style for this book.
    var effectivePageTurnStyle: PageTurnStyle {
        effective?.pageTurnStyle ?? globalSettings.pageTurnStyle
    }

    /// True while we want the JS to lay the chapter out as columns.
    /// False for Scroll mode.
    var paginatedMode: Bool {
        effectivePageTurnStyle != .scroll
    }

    // MARK: - Lifecycle

    /// Try to parse the epub and pick a starting chapter.
    func loadBook() async {
        guard let fileURL = currentEpubURL() else {
            loadError = "Couldn't find this book's file."
            return
        }

        do {
            let parsed = try EpubParser.parse(fileURL)
            self.parsed = parsed

            // Pick the chapter to land on: saved position, or first linear.
            let startHref =
                book.lastChapterHref
                ?? parsed.spine.first(where: { $0.linear })?.href
                ?? parsed.spine.first?.href
            self.currentChapterHref = startHref

            // Prime the pagination engine with the spine index so
            // book-level progress can be computed from the first tick.
            pagination.willLoadChapter(
                spineIndex: PageNavigator.spineIndex(of: startHref, in: parsed.spine) ?? 0,
                spineCount: parsed.spine.count
            )

            if book.lastReadDate == nil {
                self.typographyPromptShown = true
            }
        } catch let parserError as EpubParserError {
            loadError = parserError.errorDescription ?? "Couldn't open this book."
        } catch {
            loadError = "Couldn't open this book: \(error.localizedDescription)"
        }
    }

    /// Resolve the URL on disk for the book's epub file.
    /// TODO: integrate with the iCloud module to trigger downloads when
    /// the file is cloud-only.
    private func currentEpubURL() -> URL? {
        switch book.storageLocation {
        case .iCloudDrive:
            guard let rel = book.iCloudDrivePath else { return nil }
            return URL(fileURLWithPath: rel)
        case .localOnly:
            guard let rel = book.localFallbackPath else { return nil }
            return URL(fileURLWithPath: rel)
        }
    }

    // MARK: - JS bridge integration

    /// Route a message from the PaginationJS bridge into the engine,
    /// then persist the resulting position.
    func handlePaginationMessage(_ message: PaginationMessage) {
        switch message {
        case .pagination(let total, let current, let paginated):
            pagination.reportPagination(
                total: total,
                current: current,
                paginated: paginated
            )
        case .pageChanged(let current):
            pagination.reportPageChanged(to: current)
        case .scrollProgress(let progress):
            pagination.reportScrollProgress(progress)
        }
        savePositionDebounced()
    }

    // MARK: - Chrome interactions

    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            chromeVisible.toggle()
        }
    }

    // MARK: - Position persistence

    /// Debounce window for position saves. Firing SwiftData saves on
    /// every scroll tick would thrash the context; a short debounce
    /// keeps the latest-valid position on disk within ~1 second of
    /// idle.
    private var saveTask: Task<Void, Never>?

    /// Schedule a save of the current position. Coalesces back-to-back
    /// calls (e.g. during a fast Slide scroll) into one SwiftData
    /// write.
    func savePositionDebounced() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.savePositionNow()
        }
    }

    /// Write the current chapter + progress onto the Book. SwiftData
    /// will pick it up on the next context save; we don't force-save
    /// here because the context lives at app scope.
    func savePositionNow() async {
        guard let href = currentChapterHref else { return }
        book.lastChapterHref = href
        book.lastScrollOffset = pagination.chapterProgress
        book.lastReadDate = Date()
        book.readingProgress = pagination.bookProgress
    }
}
