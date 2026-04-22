//
//  BookTypographyMode.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The three modes a single book can be rendered in. Set by the first-open
//  typography prompt (Rendering Engine §4.6) and stored permanently on the
//  Book SwiftData record.
//
//  WHY IT EXISTS:
//  This single enum controls the entire CSS injection path for a book:
//    .publisherDefault → inject NOTHING (let the epub's CSS be authoritative,
//                       except for theme background and a safety floor)
//    .userDefaults     → inject the user's global ReaderSettings in full
//    .custom           → inject the merged ReaderSettings + BookReaderOverrides
//
//  See EffectiveSettings.swift for how this enum drives the merge.
//

import Foundation

/// How a particular book should be styled.
///
/// The default for a brand-new book before the first-open prompt is shown
/// is `.userDefaults`. This is the safe choice: if a user somehow opens a
/// book without seeing the prompt (an edge case after a crash mid-prompt,
/// for example) they get their preferred reading style rather than a
/// surprise rendering.
enum BookTypographyMode: String, Codable, CaseIterable {

    /// The epub's own CSS is authoritative. Codex injects only the theme
    /// background/text colour and a minimum font-size floor (~10pt) so a
    /// genuinely broken epub doesn't render at 4pt.
    case publisherDefault

    /// The user's global `ReaderSettings` is applied in full. The epub's
    /// own font, size, leading, etc. are overridden.
    case userDefaults

    /// The user's `ReaderSettings` merged with this book's
    /// `BookReaderOverrides` (per-book adjustments take precedence).
    case custom

    var displayName: String {
        switch self {
        case .publisherDefault: return "Publisher's Style"
        case .userDefaults:     return "My Defaults"
        case .custom:           return "Custom for this book"
        }
    }
}
