//
//  ClipboardWriter.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Puts a passage on the iOS clipboard in two representations
//  simultaneously — rich text and plain text — so apps that support
//  rich paste use the formatted version and apps that don't fall back
//  to plain text. Defined in Module 5 (Share & Transfer) §3.
//
//  WHY ITS OWN FILE:
//  UIPasteboard's API for setting multiple representations at once is
//  awkward (a dictionary keyed by UTI). Wrapping it here means callers
//  write `ClipboardWriter.put(rich:plain:)` and don't have to know
//  about NSPasteboard.PasteboardType keys.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

enum ClipboardWriter {

    /// Place rich text + plain text on the system pasteboard. Apps
    /// that paste rich content (Notes, Pages, Mail) will get the rich
    /// representation; everything else gets plain text.
    ///
    /// Convert the rich NSAttributedString to RTF Data here rather
    /// than in the caller — RTF is the format Apple's NSAttributedString
    /// pasteboard reader expects.
    static func put(rich: NSAttributedString, plain: String) {
        var item: [String: Any] = [
            UTType.utf8PlainText.identifier: plain
        ]

        if let rtfData = try? rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            item[UTType.rtf.identifier] = rtfData
        }

        UIPasteboard.general.setItems([item])
    }
}
