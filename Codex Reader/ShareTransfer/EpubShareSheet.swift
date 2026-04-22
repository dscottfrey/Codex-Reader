//
//  EpubShareSheet.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A SwiftUI bridge to UIActivityViewController for sharing an epub
//  file or an annotation export. Defined in Module 5 (Share & Transfer)
//  §2.1.
//
//  WHY UIActivityViewController:
//  AirDrop, Mail, iMessage, Save to Files, and any installed share
//  extension all come for free. Building a custom share UI would
//  duplicate iOS functionality and lose those integrations.
//
//  WHY THE FILE COPIED TO TEMP FIRST:
//  The directive (§2.1) is explicit: "the epub file path passed to
//  UIActivityViewController must be a directly readable file — copy
//  to a temporary location first if the live iCloud Drive path might
//  be security-scoped or unavailable during the share operation." We
//  honour that here.
//

import SwiftUI
import UIKit

/// SwiftUI wrapper around UIActivityViewController. Present this with
/// `.sheet(isPresented:)` and pass a list of items (file URLs, strings,
/// images) to share.
struct EpubShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Build a temp-copy URL of an epub for safe sharing — see the file
/// header for why the copy step matters.
enum EpubShareHelper {

    /// Copy `epubURL` into the app's temp directory and return the new
    /// URL. The caller hands this to `EpubShareSheet(items: [url])`.
    static func tempCopy(of epubURL: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: epubURL, to: dest)
        return dest
    }
}
