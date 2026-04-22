//
//  TOCParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Parses the table of contents from one of the two formats epub uses —
//  the epub 3 navigation document (`<nav epub:type="toc">`) or the epub
//  2 NCX file (`<navMap>`/`<navPoint>`) — and returns a hierarchical
//  `[ParsedEpub.TocEntry]`. Step 4 of the Rendering Engine §3.2 pipeline.
//
//  WHY TWO PARSERS IN ONE FILE:
//  The file is short. Both parsers share the same output type, they're
//  selected by the same callsite, and keeping them together makes it
//  obvious that the two branches are the only options (NCX, nav, or
//  synthesised fallback).
//
//  EPUB 3 NAV DOCUMENT SHAPE:
//  <nav epub:type="toc">
//    <ol>
//      <li><a href="chapter01.xhtml">Chapter 1</a></li>
//      <li>
//        <a href="chapter02.xhtml">Chapter 2</a>
//        <ol><li><a href="chapter02.xhtml#s1">Section 1</a></li></ol>
//      </li>
//    </ol>
//  </nav>
//
//  EPUB 2 NCX SHAPE:
//  <navMap>
//    <navPoint>
//      <navLabel><text>Chapter 1</text></navLabel>
//      <content src="chapter01.xhtml"/>
//      <navPoint>...nested...</navPoint>
//    </navPoint>
//  </navMap>
//
//  The two formats look different on paper but they encode the same
//  information and the output is the same `TocEntry` tree.
//

import Foundation

enum TOCParser {

    /// Parse an epub 3 nav document (XHTML with a `<nav epub:type="toc">`
    /// element). Returns an empty array if no TOC nav is present —
    /// EpubParser then falls through to NCX or spine synthesis.
    static func parseNavDocument(_ data: Data) -> [ParsedEpub.TocEntry] {
        let delegate = NavDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.rootEntries
    }

    /// Parse an epub 2 NCX document.
    static func parseNCX(_ data: Data) -> [ParsedEpub.TocEntry] {
        let delegate = NCXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.rootEntries
    }
}

// MARK: - Shared helpers

/// Mutable tree node we can build up during parse. Flattened to
/// immutable ParsedEpub.TocEntry values on return.
private final class MutableTocNode {
    var title: String = ""
    var href: String = ""
    var children: [MutableTocNode] = []

    func snapshot() -> ParsedEpub.TocEntry {
        ParsedEpub.TocEntry(
            title: title,
            href: href,
            children: children.map { $0.snapshot() }
        )
    }
}

// MARK: - Epub 3 nav document

/// Walks an XHTML nav document. The interesting shape is nested
/// `<ol>` → `<li>` → `<a>`, so we push a new node on every `<li>` we
/// encounter inside the toc `<nav>` and pop when the `<li>` ends.
private final class NavDelegate: NSObject, XMLParserDelegate {

    var rootEntries: [ParsedEpub.TocEntry] = []

    private var inTocNav = false
    private var stack: [MutableTocNode] = []
    private var pendingHref: String?
    private var captureText = false
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = elementName.lowercased()

        switch name {
        case "nav":
            // Look for epub:type="toc" — either the prefixed form or
            // the un-prefixed one.  shouldProcessNamespaces is off, so
            // the attribute comes through as "epub:type".
            let type = attributeDict["epub:type"] ?? attributeDict["type"] ?? ""
            if type.contains("toc") { inTocNav = true }

        case "li" where inTocNav:
            // A new entry opens. It becomes a child of the current top
            // of the stack, or a root entry if the stack is empty.
            let node = MutableTocNode()
            if let parent = stack.last {
                parent.children.append(node)
            }
            stack.append(node)

        case "a" where inTocNav:
            // The href on this anchor belongs to the innermost <li>.
            pendingHref = attributeDict["href"]
            captureText = true
            textBuffer = ""

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureText { textBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()

        switch name {
        case "a" where inTocNav:
            if let current = stack.last {
                current.title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                current.href = pendingHref ?? ""
            }
            pendingHref = nil
            captureText = false

        case "li" where inTocNav:
            // Closing the entry. If it was a root-level entry, emit it.
            guard let finished = stack.popLast() else { return }
            if stack.isEmpty {
                rootEntries.append(finished.snapshot())
            }

        case "nav" where inTocNav:
            inTocNav = false

        default:
            break
        }
    }
}

// MARK: - Epub 2 NCX

/// Walks an NCX document. Structurally the same tree as the nav doc,
/// just different element names — <navPoint> instead of <li>, with
/// <navLabel><text> for the title and <content src> for the href.
private final class NCXDelegate: NSObject, XMLParserDelegate {

    var rootEntries: [ParsedEpub.TocEntry] = []

    private var stack: [MutableTocNode] = []
    private var inText = false
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "navPoint":
            let node = MutableTocNode()
            if let parent = stack.last {
                parent.children.append(node)
            }
            stack.append(node)

        case "content":
            if let current = stack.last,
               let src = attributeDict["src"] {
                current.href = src
            }

        case "text":
            inText = true
            textBuffer = ""

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { textBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "text":
            if inText, let current = stack.last, current.title.isEmpty {
                current.title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            inText = false

        case "navPoint":
            guard let finished = stack.popLast() else { return }
            if stack.isEmpty {
                rootEntries.append(finished.snapshot())
            }

        default:
            break
        }
    }
}
