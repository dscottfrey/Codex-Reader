//
//  ContainerParser.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Reads META-INF/container.xml and returns the path to the OPF
//  package document. Used by EpubParser as Step 2 of the parse pipeline
//  (Rendering Engine §3.2).
//
//  WHY IT'S A FILE OF ITS OWN:
//  container.xml is a one-job document (it points at the OPF) and its
//  XML shape is different from the OPF and the NCX. Keeping a narrow
//  XMLParser delegate per document type means each delegate stays small
//  and easy to read — one rule in CLAUDE.md §6.3 "no monolithic files."
//
//  THE SHAPE BEING PARSED:
//  <container>
//    <rootfiles>
//      <rootfile full-path="OEBPS/content.opf" media-type="..."/>
//    </rootfiles>
//  </container>
//
//  Epubs can technically list multiple rootfiles, but the epub spec
//  requires the first rootfile to be the authoritative package document.
//  We take the first one and stop.
//

import Foundation

enum ContainerParser {

    /// Parse `container.xml` bytes and return the `full-path` attribute
    /// of the first `<rootfile>` element. nil on any parse failure —
    /// EpubParser surfaces this as `containerXmlNotFound` because a
    /// container with no rootfile is functionally equivalent to no
    /// container at all.
    static func findOPFPath(in containerXML: Data) -> String? {
        let delegate = ContainerDelegate()
        let parser = XMLParser(data: containerXML)
        parser.delegate = delegate
        parser.parse()
        return delegate.opfPath
    }
}

private final class ContainerDelegate: NSObject, XMLParserDelegate {

    /// The `full-path` attribute of the first `<rootfile>` element seen.
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        // Only the first rootfile is authoritative. Ignore anything
        // after we've already captured a path.
        guard opfPath == nil,
              elementName == "rootfile",
              let path = attributeDict["full-path"]
        else { return }
        opfPath = path
    }
}
