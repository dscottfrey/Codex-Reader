//
//  OPDSFeedParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Parses an OPDS Atom feed XML document into OPDSEntry values.
//
//  WHY FOUNDATION'S XMLParser:
//  OPDS is just Atom XML with a small set of relevant elements (title,
//  author, summary, link). Foundation's XMLParser handles the streaming
//  parse without requiring a third-party library, and it's all the
//  parser API we need (no XPath, no schema validation).
//
//  WHAT'S DELIBERATELY MINIMAL:
//  We extract only the fields the UI uses: title, author, series,
//  summary, cover URL, download URL. Authentication-related elements
//  (OAuth links, etc.) are not parsed because Codex's auth model is
//  Basic Auth via the Keychain (directive §2.2). Acquisition links are
//  identified by their `rel` attribute including "acquisition" and a
//  `type` of `application/epub+zip`.
//

import Foundation

/// Parses an OPDS feed XML payload into entries.
final class OPDSFeedParser: NSObject, XMLParserDelegate {

    // MARK: - Output

    private(set) var entries: [OPDSEntry] = []
    private(set) var nextPageURL: URL?

    // MARK: - Parse state

    /// True while we are inside an <entry> element.
    private var inEntry = false

    /// Accumulated CDATA / text for the currently-open element.
    private var elementText = ""

    /// Per-entry under-construction values.
    private var currentID = ""
    private var currentTitle = ""
    private var currentAuthor = ""
    private var currentSeries: String?
    private var currentSummary: String?
    private var currentCover: URL?
    private var currentDownload: URL?

    /// Are we currently inside the <author> element? Author element
    /// contains a <name> child whose text is the actual author name.
    private var inAuthor = false

    // MARK: - Public API

    /// Parse an OPDS feed payload. Returns the parsed page on success,
    /// nil on parse failure.
    static func parse(_ data: Data) -> OPDSFeedPage? {
        let parser = OPDSFeedParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return nil }
        return OPDSFeedPage(entries: parser.entries, nextPageURL: parser.nextPageURL)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        elementText = ""
        switch elementName {
        case "entry":
            inEntry = true
            currentID = ""; currentTitle = ""; currentAuthor = ""
            currentSeries = nil; currentSummary = nil
            currentCover = nil; currentDownload = nil
        case "author":
            inAuthor = true
        case "link":
            handleLink(attrs: attributeDict)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        elementText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "entry":
            if !currentTitle.isEmpty {
                entries.append(OPDSEntry(
                    id: currentID.isEmpty ? UUID().uuidString : currentID,
                    title: currentTitle,
                    author: currentAuthor,
                    series: currentSeries,
                    summary: currentSummary,
                    coverURL: currentCover,
                    downloadURL: currentDownload
                ))
            }
            inEntry = false
        case "id" where inEntry:
            currentID = text
        case "title" where inEntry:
            currentTitle = text
        case "name" where inAuthor:
            currentAuthor = text
        case "author":
            inAuthor = false
        case "summary" where inEntry:
            currentSummary = text
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Inspect a <link> element's attributes. The `rel` and `type`
    /// pair tells us what the link points to: an acquisition (download),
    /// a cover image, or pagination.
    private func handleLink(attrs: [String: String]) {
        let rel  = attrs["rel"]  ?? ""
        let type = attrs["type"] ?? ""
        let href = attrs["href"] ?? ""
        guard let url = URL(string: href) else { return }

        if inEntry {
            if rel.contains("acquisition"), type.contains("epub") {
                currentDownload = url
            } else if rel.contains("image"), type.hasPrefix("image/") {
                currentCover = url
            }
        } else {
            if rel == "next" {
                nextPageURL = url
            }
        }
    }
}
