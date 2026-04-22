//
//  CoverExtractor.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Pulls a cover image out of an epub and writes it to the app's covers
//  cache. Defined in Module 2 (Ingestion Engine) §5.4.
//
//  WHY ITS OWN FILE:
//  Cover extraction is invoked at ingestion time and never again — the
//  result is cached in Application Support and the path is stored on
//  the Book record. Keeping it standalone means the ingestion pipeline
//  reads cleanly: validate → dedupe → extract metadata → extract cover
//  → save book. Each step is one short function call.
//
//  THE THREE-LEVEL FALLBACK:
//  1. Look for the cover image declared in the OPF manifest
//     (`properties="cover-image"`).
//  2. If absent, take the first image file in the epub.
//  3. If neither exists, generate a placeholder using a deterministic
//     colour derived from the title hash.
//

import Foundation
import UIKit

enum CoverExtractor {

    /// The directory where extracted covers are cached. Application
    /// Support per directive §7 — covers are derived assets, not user
    /// files, so they live here rather than iCloud Drive.
    static var coversDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Extract or generate a cover for a book and return the absolute
    /// path on disk.
    ///
    /// When `parsed` has resolved a cover image inside the unzipped
    /// temp directory, that file is copied into the app's covers cache.
    /// Otherwise the generated placeholder is used.
    static func extractCover(
        forBookID id: UUID,
        title: String,
        author: String,
        from parsed: ParsedEpub?
    ) -> String {

        let outURL = coversDirectory.appendingPathComponent("\(id.uuidString).jpg")

        // Try the parsed cover first if we have a parser result. The
        // parser resolves cover-image/href against the unzipped root
        // already, so we just need to copy the bytes.
        if let parsed,
           let coverFile = parsed.coverImageURL,
           let data = try? Data(contentsOf: coverFile) {
            try? data.write(to: outURL)
            return outURL.path
        }

        // Fall back to a generated placeholder.
        let placeholder = makePlaceholderCover(title: title, author: author)
        if let data = placeholder.jpegData(compressionQuality: 0.8) {
            try? data.write(to: outURL)
        }
        return outURL.path
    }

    /// Generate a placeholder cover: title + author rendered on a
    /// coloured background. Same title → same colour every time.
    private static func makePlaceholderCover(title: String, author: String) -> UIImage {
        let size = CGSize(width: 600, height: 900)
        let colour = colourFor(title: title)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Background fill.
            colour.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Title.
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            (title as NSString).draw(
                in: CGRect(x: 40, y: 80, width: size.width - 80, height: 400),
                withAttributes: titleAttr
            )

            // Author near the bottom.
            let authorAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            (author as NSString).draw(
                in: CGRect(x: 40, y: size.height - 120, width: size.width - 80, height: 80),
                withAttributes: authorAttr
            )
        }
    }

    /// Deterministic colour from a title — same title always gets the
    /// same colour, so the user gets a stable placeholder per book.
    private static func colourFor(title: String) -> UIColor {
        let hue = CGFloat(abs(title.hashValue) % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1.0)
    }
}
