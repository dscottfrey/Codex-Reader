//
//  EffectiveSettings.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The merge function that decides what typography to inject for a given
//  book. Defined in Module 1 (Rendering Engine) §7.4.
//
//  WHY IT EXISTS:
//  The same global ReaderSettings might be applied differently to two
//  books: one in publisher mode (no overrides), one in custom mode (some
//  overrides). All three callers (CSSBuilder, the live-preview update
//  path, and the settings panel that shows current values) must agree on
//  what's effective for a given book. Centralising the merge here means
//  there's exactly one rule and it's documented in one place.
//
//  RETURN VALUE SEMANTICS:
//  Returns `nil` when the book is in publisherDefault mode. The renderer
//  treats nil as "do not inject user CSS — only inject theme background
//  and the safety floor." This is deliberate: a settings struct full of
//  user values would not represent "respect the publisher" correctly,
//  but nil is unambiguous.
//

import Foundation

/// The Rendering Engine asks this function: "Given the user's global
/// settings and this book, what styling should I inject?"
///
/// - Parameters:
///   - global: The user's global ReaderSettings (their personal defaults).
///   - book:   The book about to be rendered. Its `typographyMode` and
///             `typographyOverrides` drive the merge logic.
/// - Returns: Either a fully-populated `ReaderSettings` to inject in
///   full, or `nil` to mean "this book is in publisher mode — only inject
///   theme background and the minimum font floor."
@MainActor
func effectiveSettings(global: ReaderSettings, book: Book) -> ReaderSettings? {

    switch book.typographyMode {

    case .publisherDefault:
        // The epub's CSS is in charge. Theme and font floor are still
        // applied separately by the renderer — see CSSBuilder.
        return nil

    case .userDefaults:
        // No per-book overrides. Global settings apply in full.
        return global

    case .custom:
        // Merge: take global as the base, apply each non-nil override on top.
        // The accessor returns `.empty` if no overrides have been set yet,
        // so we always have something to merge.
        let overrides = book.typographyOverrides
        return ReaderSettings(
            fontSize:      overrides.fontSize      ?? global.fontSize,
            fontFamily:    overrides.fontFamily    ?? global.fontFamily,
            useBookFonts:  overrides.useBookFonts  ?? global.useBookFonts,
            lineSpacing:   overrides.lineSpacing   ?? global.lineSpacing,
            letterSpacing: overrides.letterSpacing ?? global.letterSpacing,
            textAlignment: overrides.textAlignment ?? global.textAlignment,
            theme:         overrides.theme         ?? global.theme,
            pageTurnStyle: overrides.pageTurnStyle ?? global.pageTurnStyle,
            marginTop:     overrides.marginTop     ?? global.marginTop,
            marginBottom:  overrides.marginBottom  ?? global.marginBottom,
            marginLeft:    overrides.marginLeft    ?? global.marginLeft,
            marginRight:   overrides.marginRight   ?? global.marginRight
        )
    }
}

/// The theme to apply to a book even when it's in publisher mode. The
/// theme's background and text colours always override the epub's,
/// because (a) it has to match the rest of the app chrome and (b) dark
/// mode would otherwise render as light-on-light, unreadable.
///
/// In `.publisherDefault` and `.userDefaults` the answer is the global
/// theme. In `.custom` the per-book theme override (if any) wins.
@MainActor
func effectiveTheme(global: ReaderSettings, book: Book) -> ReaderTheme {
    if book.typographyMode == .custom,
       let perBook = book.typographyOverrides.theme {
        return perBook
    }
    return global.theme
}
