//
//  EpubParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The top-level epub parser — orchestrates the four-step pipeline
//  described in Rendering Engine directive §3.2:
//    1. Unzip (EpubArchive).
//    2. Find the OPF path (ContainerParser).
//    3. Parse the OPF for metadata, manifest, spine, cover
//       (OPFParser + resolution against the filesystem).
//    4. Parse the TOC (TOCParser — nav document or NCX, falling back
//       to a spine-synthesised TOC when neither is present).
//
//  Returns a fully-populated ParsedEpub. Throws EpubParserError only
//  when the file is so broken it can't be read at all — missing
//  container, missing OPF, empty spine. Every other defect degrades
//  gracefully: missing TOC → synthesised, missing cover → nil, missing
//  language → "en".
//
//  WHY IT'S THIN:
//  Each step is a small focused helper living in its own file. This
//  file is the orchestration layer — what reads top-to-bottom like the
//  steps in the directive.
//

import Foundation

enum EpubParser {

    /// Parse the epub at `url`. See file header for the step-by-step.
    static func parse(_ url: URL) throws -> ParsedEpub {

        // STEP 1 — unzip into a fresh temp directory.
        let unzippedRoot = try EpubArchive.unzip(url)

        // STEP 2 — read META-INF/container.xml to find the OPF path.
        let containerURL = unzippedRoot
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        guard let containerData = try? Data(contentsOf: containerURL),
              let opfRelativePath = ContainerParser.findOPFPath(in: containerData)
        else {
            throw EpubParserError.containerXmlNotFound
        }

        // STEP 3 — parse the OPF.
        let opfURL = unzippedRoot.appendingPathComponent(opfRelativePath)
        guard let opfData = try? Data(contentsOf: opfURL),
              let opf = OPFParser.parse(opfData)
        else {
            throw EpubParserError.opfNotFound
        }

        // Every href in the OPF is relative to the OPF's directory, not
        // to the unzipped root. Resolve that base once.
        let opfDirectory = opfURL.deletingLastPathComponent()

        // Build a lookup from manifest id → ManifestItem. We need this
        // both to turn spine idrefs into real files and to resolve the
        // epub 2 cover pointer.
        var manifestItems: [String: ParsedEpub.ManifestItem] = [:]
        manifestItems.reserveCapacity(opf.manifest.count)
        for raw in opf.manifest {
            manifestItems[raw.id] = ParsedEpub.ManifestItem(
                id: raw.id,
                href: raw.href,
                mediaType: raw.mediaType,
                absoluteURL: opfDirectory.appendingPathComponent(raw.href)
            )
        }

        // Resolve the spine against the manifest. An idref that doesn't
        // appear in the manifest is skipped — a malformed OPF shouldn't
        // crash the parser, but an unmatched idref has no href to load.
        var spine: [ParsedEpub.SpineItem] = []
        spine.reserveCapacity(opf.spine.count)
        for raw in opf.spine {
            guard let item = manifestItems[raw.idref] else { continue }
            spine.append(ParsedEpub.SpineItem(
                id: raw.idref,
                href: item.href,
                absoluteURL: item.absoluteURL,
                linear: raw.linear
            ))
        }

        guard !spine.isEmpty else { throw EpubParserError.spineEmpty }

        // Cover resolution — try epub 3 first, fall back to epub 2.
        let coverURL = resolveCoverURL(opf: opf, manifestItems: manifestItems)

        // STEP 4 — TOC. Try nav doc, then NCX, then synthesise.
        let tocEntries = resolveTOC(
            opf: opf,
            manifestItems: manifestItems,
            spine: spine
        )

        // Fold multiple <dc:creator> entries into a single display
        // string. Empty string if there's literally no creator in the
        // OPF — the library shows "Unknown Author" in that case.
        let author = opf.creators.joined(separator: ", ")

        return ParsedEpub(
            title: opf.title,
            author: author,
            language: opf.language,
            coverImageURL: coverURL,
            spine: spine,
            tocEntries: tocEntries,
            manifestItems: manifestItems,
            unzippedRoot: unzippedRoot
        )
    }

    // MARK: - Cover resolution

    /// Find the cover image URL. Epub 3 marks it on the manifest item
    /// (`properties="cover-image"`); epub 2 declares it via a separate
    /// `<meta name="cover" content="<id>"/>` element that points at a
    /// manifest id. Both formats end up returning the same thing — a
    /// URL inside the unzipped tree — so callers don't need to know
    /// which form the book used.
    private static func resolveCoverURL(
        opf: OPFContents,
        manifestItems: [String: ParsedEpub.ManifestItem]
    ) -> URL? {
        // Epub 3: manifest item with properties containing "cover-image".
        for raw in opf.manifest {
            if let props = raw.properties,
               props.contains("cover-image"),
               let item = manifestItems[raw.id] {
                return item.absoluteURL
            }
        }
        // Epub 2: meta name="cover" content="<manifest-id>".
        if let id = opf.epub2CoverID,
           let item = manifestItems[id] {
            return item.absoluteURL
        }
        return nil
    }

    // MARK: - TOC resolution

    /// Try the epub 3 nav document first, then the epub 2 NCX, then
    /// synthesise a flat TOC from the spine. Per directive §3.2: better
    /// to show "Chapter 1 / Chapter 2" than to crash.
    private static func resolveTOC(
        opf: OPFContents,
        manifestItems: [String: ParsedEpub.ManifestItem],
        spine: [ParsedEpub.SpineItem]
    ) -> [ParsedEpub.TocEntry] {

        // Epub 3 — a manifest item with properties="nav".
        if let navItem = opf.manifest.first(where: {
            $0.properties?.contains("nav") == true
        }),
           let resolved = manifestItems[navItem.id],
           let data = try? Data(contentsOf: resolved.absoluteURL) {
            let entries = TOCParser.parseNavDocument(data)
            if !entries.isEmpty { return entries }
        }

        // Epub 2 — a manifest item with media-type=application/x-dtbncx+xml.
        if let ncxItem = opf.manifest.first(where: {
            $0.mediaType == "application/x-dtbncx+xml"
        }),
           let resolved = manifestItems[ncxItem.id],
           let data = try? Data(contentsOf: resolved.absoluteURL) {
            let entries = TOCParser.parseNCX(data)
            if !entries.isEmpty { return entries }
        }

        // Fallback — synthesise "Chapter N" entries from the linear
        // part of the spine. Non-linear items (footnotes, previews) are
        // deliberately excluded to keep the synthesised TOC focused on
        // the main reading flow.
        let linearSpine = spine.filter { $0.linear }
        let source = linearSpine.isEmpty ? spine : linearSpine
        return source.enumerated().map { index, item in
            ParsedEpub.TocEntry(
                title: "Chapter \(index + 1)",
                href: item.href,
                children: []
            )
        }
    }
}
