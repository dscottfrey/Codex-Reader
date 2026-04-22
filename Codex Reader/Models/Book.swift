//
//  Book.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The SwiftData record for a single book in the library. Defined in
//  Library Manager directive §15. Lives here in /Models because it is
//  referenced by every other module (rendering opens it, ingestion creates
//  it, sync mirrors it, annotations attach to it).
//
//  WHY THE STORAGE STRATEGY:
//  Apple's SwiftData with the CloudKit-backed ModelConfiguration handles
//  most of the cross-device sync (Sync Engine directive §10). To work with
//  CloudKit, every property must either be Optional or have a default
//  value, and relationships must be optional. Hence the heavy use of `=`
//  defaults and Optionals you will see throughout.
//
//  WHY typographyOverridesData IS A Data BLOB:
//  Per the directive (§7.3) the per-book overrides are stored as JSON so
//  the structure can grow new fields without a SwiftData migration. When
//  you need to read or write the overrides, use the `typographyOverrides`
//  computed property below, which handles the encode/decode for you.
//

import Foundation
import SwiftData

@Model
final class Book {

    // MARK: - Identity & metadata

    /// A stable identifier independent of file path or title — this is
    /// what every other record (annotations, reading position) refers to.
    @Attribute(.unique) var id: UUID = UUID()

    var title: String = ""
    var author: String = ""
    var series: String?
    var seriesNumber: Double?
    var language: String = "en"
    var publisher: String?
    var epubVersion: String = "3.0"

    // MARK: - File location (Ingestion Engine §8)

    /// Path within `iCloud Drive/Codex/Library/` — relative, not absolute,
    /// so the same record works on iPhone and iPad despite different
    /// container URLs.
    var iCloudDrivePath: String?

    /// Absolute path in Application Support, used only when in
    /// `.localOnly` mode (the iCloud bypass).
    var localFallbackPath: String?

    /// Where to look for the epub right now. Toggled by user actions like
    /// "Keep Local Only" and "Upload to iCloud".
    var storageLocationRaw: String = StorageLocation.iCloudDrive.rawValue

    /// Convenience accessor on top of `storageLocationRaw`. SwiftData with
    /// CloudKit prefers raw types so we store the rawValue and project a
    /// typed view.
    var storageLocation: StorageLocation {
        get { StorageLocation(rawValue: storageLocationRaw) ?? .iCloudDrive }
        set { storageLocationRaw = newValue.rawValue }
    }

    /// The current iCloud file state, refreshed by the NSMetadataQuery
    /// monitor in the iCloud module. This is informational — the canonical
    /// "where is this file" answer is `storageLocation`.
    var iCloudFileStateRaw: String = ICloudFileState.synced.rawValue
    var iCloudFileState: ICloudFileState {
        get { ICloudFileState(rawValue: iCloudFileStateRaw) ?? .synced }
        set { iCloudFileStateRaw = newValue.rawValue }
    }

    // MARK: - Cover

    /// Filename inside Application Support/covers/ — not iCloud Drive,
    /// because covers are derived assets we can regenerate from the epub.
    var coverCachePath: String?

    // MARK: - File metadata

    var fileSize: Int64 = 0
    var fileSHA256: String?       // for exact-file-match dedupe (Ingestion §5.2)
    var wordCountEstimate: Int?
    var dateAdded: Date = Date()
    var lastReadDate: Date?
    var lastReadDeviceName: String?

    // MARK: - Reading state

    /// Progress 0.0–1.0. If `customEndPoint` is set, progress is reported
    /// against that end point rather than the full epub length.
    var readingProgress: Double = 0.0
    var isFinished: Bool = false
    var customEndPoint: Double?
    var didNotFinish: Bool = false
    var didNotFinishDate: Date?

    /// The chapter href (e.g. `OEBPS/chapter07.xhtml`) the user was last
    /// reading. Stored alongside scrollOffset so we can resume precisely.
    var lastChapterHref: String?
    var lastScrollOffset: Double = 0.0

    // MARK: - Typography (Rendering Engine §7.2 & §7.3)

    /// Which of the three rendering modes applies to this book.
    var typographyModeRaw: String = BookTypographyMode.userDefaults.rawValue
    var typographyMode: BookTypographyMode {
        get { BookTypographyMode(rawValue: typographyModeRaw) ?? .userDefaults }
        set { typographyModeRaw = newValue.rawValue }
    }

    /// JSON-encoded `BookReaderOverrides`. Only meaningful when
    /// `typographyMode == .custom`.
    var typographyOverridesData: Data?

    /// Computed accessor that handles the JSON encode/decode. Returns
    /// `.empty` if nothing has been stored yet, so callers don't have to
    /// guard against nil. Setting to `.empty` clears the stored blob.
    var typographyOverrides: BookReaderOverrides {
        get {
            guard let data = typographyOverridesData,
                  let decoded = try? JSONDecoder().decode(BookReaderOverrides.self, from: data)
            else { return .empty }
            return decoded
        }
        set {
            if newValue.isEmpty {
                typographyOverridesData = nil
            } else {
                typographyOverridesData = try? JSONEncoder().encode(newValue)
            }
        }
    }

    // MARK: - Bookshelf appearance (Library Manager §4.4)

    /// Hex colour extracted from the cover image at ingestion time, used
    /// as the spine background. nil → fall back to a neutral colour.
    var spineColour: String?

    /// True = spine text should be white; false = spine text should be
    /// dark. Computed from `spineColour` luminance at ingestion time and
    /// stored so we don't recompute per-render.
    var spineTextIsLight: Bool = false

    // MARK: - Sidecar

    /// When the .codex sidecar file was last written for this book.
    /// Sync Engine directive §12.
    var sidecarLastWritten: Date?

    // MARK: - Init

    /// Create a new Book record. All fields have safe defaults so the
    /// caller only needs to fill in the parts they have at construction
    /// time — usually title and author.
    init(
        id: UUID = UUID(),
        title: String = "",
        author: String = ""
    ) {
        self.id = id
        self.title = title
        self.author = author
    }
}
