//
//  TextFormattingEngine.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The single text-pipeline used by both in-reader text sharing and
//  full annotation export. Defined in Module 5 (Share & Transfer) §3.
//
//  WHY ONE ENGINE:
//  The directive (§5.4) is explicit: "the system is not building a new
//  text pipeline for export — it is reusing the same NSAttributedString
//  conversion used for single-passage sharing." Putting both behaviours
//  in one file means we get that for free; nothing diverges.
//
//  THE TWO REPRESENTATIONS:
//  - rich text (NSAttributedString → RTF Data) preserves bold/italic
//    from the source HTML
//  - plain text drops formatting, keeps content
//  Both go onto the clipboard simultaneously when sharing — see
//  ClipboardWriter for that path.
//

import Foundation
import UIKit

enum TextFormattingEngine {

    /// Produce both rich and plain representations of a passage of text
    /// from a book, with optional attribution suffix.
    ///
    /// - Parameters:
    ///   - htmlOrText: The raw text or HTML fragment as it appeared in
    ///     the epub. If it's HTML, `parseHTML` builds an
    ///     NSAttributedString that preserves bold/italic. If it's plain
    ///     text, both representations are the same string.
    ///   - book: For the attribution suffix.
    ///   - includeAttribution: Per Advanced Setting; default on.
    static func format(
        passage htmlOrText: String,
        book: Book,
        includeAttribution: Bool = true,
        parseHTML: Bool = true
    ) -> (rich: NSAttributedString, plain: String) {

        let attributed: NSAttributedString = {
            if parseHTML, let html = htmlAttributed(htmlOrText) { return html }
            return NSAttributedString(string: htmlOrText)
        }()

        // Compose the attribution suffix once, in both forms.
        let attribution = makeAttribution(book: book)

        let richMutable = NSMutableAttributedString(attributedString: attributed)
        if includeAttribution {
            richMutable.append(NSAttributedString(string: "\n\n" + attribution))
        }

        var plain = attributed.string
        if includeAttribution {
            plain += "\n\n" + attribution
        }

        return (richMutable, plain)
    }

    /// Attempt to interpret a string as HTML and return an attributed
    /// representation. NSAttributedString's html init runs on the main
    /// thread (it spins up a tiny HTML parser internally) so callers
    /// should be on @MainActor.
    @MainActor
    private static func htmlAttributed(_ html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    /// The single attribution line — the directive's exact wording is
    /// `— [Book Title], [Author]`.
    private static func makeAttribution(book: Book) -> String {
        let title = book.title.isEmpty ? "Untitled" : book.title
        let author = book.author.isEmpty ? "" : ", \(book.author)"
        return "— \(title)\(author)"
    }
}
