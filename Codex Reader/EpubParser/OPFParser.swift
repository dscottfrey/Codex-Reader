//
//  OPFParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Parses an epub's OPF package document and returns the metadata
//  (title, author, language), manifest, spine, and cover image id. Step
//  3 of the Rendering Engine §3.2 pipeline.
//
//  WHY A SINGLE XMLParser PASS:
//  Everything the parser needs from the OPF is in one document, so one
//  pass is enough. XMLParser is stream-based — we collect the title,
//  first creator, language, manifest items, spine entries, and cover
//  meta tag as we encounter them, then hand the result back to
//  EpubParser for resolution against the filesystem.
//
//  EPUB 2 vs EPUB 3 COVER DECLARATIONS:
//  Epub 3 marks the cover image by tagging its manifest item with
//  `properties="cover-image"`. Epub 2 uses a separate `<meta
//  name="cover" content="..."/>` pointing at a manifest id. Both are
//  collected here; EpubParser resolves whichever is present.
//
//  WHAT THIS DOES NOT DO:
//  It does not resolve hrefs against the OPF directory. That happens in
//  EpubParser once we know `unzippedRoot` and `opfDirectory`. Keeping
//  the XMLParser delegate purely syntactic — strings in, strings out —
//  makes the parse pass easy to test and understand.
//

import Foundation

/// Raw output of the OPF parse — still-relative hrefs, no URL
/// resolution. EpubParser turns this into a ParsedEpub.
struct OPFContents {
    var title: String = ""
    var creators: [String] = []
    var language: String = "en"

    /// Manifest item id → (href, mediaType, properties). Properties is
    /// the raw `properties` attribute ("nav", "cover-image", etc.) —
    /// used by the epub 3 cover and nav document lookups.
    struct RawManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String?
    }
    var manifest: [RawManifestItem] = []

    /// Ordered list of spine `idref`s with their `linear` flag.
    struct RawSpineItem {
        let idref: String
        let linear: Bool
    }
    var spine: [RawSpineItem] = []

    /// Epub 2: `<meta name="cover" content="<id>"/>` — the content is a
    /// manifest id, which has to be resolved to an href.
    var epub2CoverID: String?
}

enum OPFParser {

    /// Parse OPF bytes and return the raw `OPFContents`. nil on a
    /// fundamental XMLParser failure — EpubParser surfaces that as
    /// `opfNotFound` since an unreadable OPF is the same user outcome
    /// as a missing one.
    static func parse(_ opfData: Data) -> OPFContents? {
        let delegate = OPFDelegate()
        let parser = XMLParser(data: opfData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        return parser.parse() ? delegate.contents : nil
    }
}

// MARK: - XMLParser delegate

private final class OPFDelegate: NSObject, XMLParserDelegate {

    var contents = OPFContents()

    // Element-scope state. We only capture text for elements we care
    // about (title, creator, language) — everything else is ignored.
    private var currentElement: String = ""
    private var currentText: String = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        // XMLParser delivers names with namespace prefixes when
        // shouldProcessNamespaces is false. Normalise by trimming the
        // prefix so matching works on both `dc:title` and `title`.
        currentElement = elementName.components(separatedBy: ":").last ?? elementName
        currentText = ""

        switch currentElement {
        case "item":
            // <item> inside <manifest>. Has id/href/media-type plus
            // optional properties.
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"],
                  let mediaType = attributeDict["media-type"]
            else { return }
            contents.manifest.append(OPFContents.RawManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: attributeDict["properties"]
            ))

        case "itemref":
            // <itemref> inside <spine>. linear defaults to "yes" when
            // the attribute is absent (epub spec §1.5.1).
            guard let idref = attributeDict["idref"] else { return }
            let linearAttr = attributeDict["linear"]?.lowercased()
            let linear = linearAttr != "no"  // default yes
            contents.spine.append(OPFContents.RawSpineItem(
                idref: idref,
                linear: linear
            ))

        case "meta":
            // Epub 2 cover declaration lives on a <meta name="cover"/>
            // with the manifest id in `content`. Epub 3 uses OPF-style
            // <meta property="..."> tags that don't have a name= attr,
            // so the name-check is enough to disambiguate.
            if attributeDict["name"]?.lowercased() == "cover",
               let id = attributeDict["content"] {
                contents.epub2CoverID = id
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.components(separatedBy: ":").last ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "title":
            // First <title> wins. epub metadata can contain multiple
            // titles (original, translated, etc.); the first one is the
            // one the library wants to display.
            if contents.title.isEmpty { contents.title = text }

        case "creator":
            // Every <dc:creator> contributes. Joined later by EpubParser.
            if !text.isEmpty { contents.creators.append(text) }

        case "language":
            if !text.isEmpty { contents.language = text }

        default:
            break
        }

        currentText = ""
    }
}
