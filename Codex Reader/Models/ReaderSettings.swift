//
//  ReaderSettings.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The user's GLOBAL typography defaults — the font, size, leading, theme,
//  and margins they want to read every book in. Defined in Module 1
//  (Rendering Engine) §2.1 and §7.1.
//
//  WHY IT EXISTS:
//  This is the foundational design idea of Codex: the user's settings are
//  ALWAYS applied to every book, overriding what the publisher encoded.
//  Apple Books does the opposite — it caps user preferences against the
//  epub's encoding. We do not.
//
//  WHERE IT'S STORED:
//  In SwiftData (so it auto-syncs via CloudKit per the Sync Engine
//  directive §4.4) plus mirrored to UserDefaults on every change so that
//  the renderer can read it synchronously at startup without waiting on
//  the SwiftData container being available. The mirror is one-way and
//  optional — the SwiftData record is the source of truth.
//

import Foundation

/// All of the typography choices a reader can make at the global level.
///
/// Codable so it can be JSON-encoded into the portable export
/// (Sync Engine §11) and into the per-book overrides blob.
///
/// `ReaderSettings` is intentionally a value type, not a `@Model`. There is
/// only ever ONE global ReaderSettings per user — it doesn't need
/// SwiftData's identity tracking. A small `ReaderSettingsRecord` SwiftData
/// model wraps it for storage and CloudKit sync — see ReaderSettingsRecord.swift.
///
/// `nonisolated` here is load-bearing: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise make
/// the synthesised `Codable` conformance main-actor-isolated. The SwiftData
/// `ReaderSettingsRecord` encodes/decodes this struct from a nonisolated
/// init / property accessor, which Swift 6 strict concurrency would refuse.
/// Opting this pure value-type out of the default isolation is the right
/// model — it has no UI state, no main-thread requirements, and is freely
/// passed across actor boundaries (portable export, sync, etc.).
nonisolated struct ReaderSettings: Codable, Equatable {

    // MARK: - Typography

    /// The body text font size in points. Range is constrained by the
    /// user-configurable min/max in Advanced Settings (§4.5), defaulting
    /// to 8pt and 72pt. The renderer applies this with `!important` so the
    /// epub's own size declarations are ignored.
    var fontSize: CGFloat

    /// The font family applied to body text. Must be a font installed on
    /// the device — system fonts plus any user-installed fonts via the iOS
    /// font management system. The renderer overrides the epub's chosen
    /// fonts (unless `useBookFonts` is on).
    var fontFamily: String

    /// When true, Codex respects whatever fonts the epub references and
    /// `fontFamily` is ignored. Off by default — most users open settings
    /// because they want to override.
    var useBookFonts: Bool

    /// Multiplier on line height. 1.0 = single line spacing, 1.4 = the
    /// comfortable default, 2.5 = the directive's specified upper bound.
    var lineSpacing: CGFloat

    /// Letter-spacing in pixels. Negative values tighten, positive values
    /// loosen. Range -2px to +4px per the directive.
    var letterSpacing: CGFloat

    /// Body text alignment. Only `.left` and `.justified` are exposed.
    var textAlignment: TextAlign

    // MARK: - Theme

    /// The currently active reading theme. May be auto-driven by Match
    /// Surroundings or the schedule — the user's last-chosen theme is what
    /// gets stored here regardless.
    var theme: ReaderTheme

    // MARK: - Page Turn

    /// The page transition style. Locked once chosen — never auto-changes
    /// based on font size or content. The only exception is the iPad
    /// portrait auto-switch to scroll (directive §2.6).
    var pageTurnStyle: PageTurnStyle

    // MARK: - Margins (in points, applied as CSS padding on body)

    var marginTop: CGFloat
    var marginBottom: CGFloat
    var marginLeft: CGFloat
    var marginRight: CGFloat

    // MARK: - Defaults

    /// The shipped-with-the-app default settings. A new install starts here.
    /// Each value is justified by the directive.
    static let `default` = ReaderSettings(
        fontSize:      18.0,         // a comfortable starting point on phone and tablet
        fontFamily:    "Georgia",    // a serif font available on all iOS devices
        useBookFonts:  false,        // override is the default — that's why people open settings
        lineSpacing:   1.4,          // matches directive §2.8 default
        letterSpacing: 0.0,          // 0 = neutral
        textAlignment: .left,        // matches directive §2.8 default
        theme:         .light,       // matches Light/Dark/Sepia order in directive §2.10
        pageTurnStyle: .curl,        // dev-cycle pick: Scott is iterating on iPad-landscape Curl in the simulator. Reverts to .slide (directive's "safe initial pick") when the dev cycle ends.
        // These look bigger than print intuition would suggest because
        // the off-screen renderer renders at half scale (Docs/HANDOFF.md
        // §2.2), so the visual result is roughly half the CSS pt value.
        // Top is extra-large so the chrome action bar clears the first
        // line of body text. Drop these back to ~20pt all around when
        // the half-size render is properly fixed.
        marginTop:     105,
        marginBottom:  55,
        marginLeft:    55,
        marginRight:   55
    )
}
