//
//  BookReaderOverrides.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The PER-BOOK adjustments a reader has made on top of their global
//  preferences. Defined in Module 1 (Rendering Engine) §7.3.
//
//  WHY IT EXISTS:
//  Sometimes a particular book reads better at a different leading, or in
//  a different font, or in a darker theme — without the user wanting to
//  change those globally. Apple Books does not allow this. Codex does, via
//  the "This Book" segmented control in the reader settings panel
//  (directive §4.2).
//
//  All fields are optional. Nil means "no override for this property —
//  use the global default." Only fields the user has explicitly touched
//  are non-nil.
//
//  WHERE IT'S STORED:
//  As a JSON-encoded blob on the Book SwiftData model
//  (`Book.typographyOverridesData`). It is only meaningful when
//  `Book.typographyMode == .custom`. The renderer's `effectiveSettings()`
//  function in EffectiveSettings.swift handles the nil-merging logic.
//

import Foundation

/// A per-book overlay on `ReaderSettings`. Each field mirrors a field of
/// `ReaderSettings`, but is Optional. A non-nil value means the user has
/// chosen to override that single property for this one book.
///
/// This struct is stored serialised as JSON on the Book record so it can
/// grow new fields without a SwiftData migration.
///
/// `nonisolated` here is load-bearing — see the same note on
/// `ReaderSettings`. The project's default actor isolation is `MainActor`,
/// which would otherwise make the synthesised `Codable` conformance
/// main-actor-isolated and conflict with the nonisolated SwiftData
/// accessor that serialises this blob on `Book`.
nonisolated struct BookReaderOverrides: Codable, Equatable {

    var fontSize: CGFloat?
    var fontFamily: String?
    var useBookFonts: Bool?
    var lineSpacing: CGFloat?
    var letterSpacing: CGFloat?
    var textAlignment: TextAlign?
    var theme: ReaderTheme?
    var pageTurnStyle: PageTurnStyle?
    var marginTop: CGFloat?
    var marginBottom: CGFloat?
    var marginLeft: CGFloat?
    var marginRight: CGFloat?

    /// An empty overrides record — every field nil. The starting state for
    /// any book that has just been switched into custom typography mode but
    /// the user hasn't moved any sliders yet.
    static let empty = BookReaderOverrides()

    /// True iff every field is nil. Equivalent to "this book has no
    /// per-book overrides set". Used by the settings panel to decide
    /// whether to show the "Custom settings active for this book"
    /// indicator (directive §4.2).
    var isEmpty: Bool {
        fontSize      == nil &&
        fontFamily    == nil &&
        useBookFonts  == nil &&
        lineSpacing   == nil &&
        letterSpacing == nil &&
        textAlignment == nil &&
        theme         == nil &&
        pageTurnStyle == nil &&
        marginTop     == nil &&
        marginBottom  == nil &&
        marginLeft    == nil &&
        marginRight   == nil
    }
}
