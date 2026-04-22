//
//  DRMDetector.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Decides whether an epub is DRM-protected. Defined in Module 2
//  (Ingestion Engine) §5.1.
//
//  WHY IT'S A QUICK CHECK BEFORE ANYTHING ELSE:
//  We want to refuse a DRM'd epub before copying it anywhere — both to
//  spare disk space and to avoid implying we did anything with the file.
//  The only check needed is for the Adobe ADEPT marker; Apple's FairPlay
//  DRM produces files that aren't valid standard epubs at all, so the
//  general epub validator will catch those without us needing a special
//  rule (per directive note in §5.1).
//
//  HOW THE DETECTION WORKS:
//  Adobe DRM places a META-INF/encryption.xml file inside the epub ZIP
//  with a `<EncryptionMethod Algorithm="...">` element referencing
//  Adobe's algorithm URI. We just need to read that one file and look
//  for the substring "adobe.com/adept". If absent → not DRM'd.
//

import Foundation

enum DRMDetector {

    /// Returns true iff `epubURL` looks like an Adobe ADEPT DRM-protected
    /// epub. Conservative: returns false on any read failure rather than
    /// blocking ingestion of a probably-fine file.
    static func isDRMProtected(_ epubURL: URL) -> Bool {
        guard let data = EpubArchive.readEntry("META-INF/encryption.xml", from: epubURL),
              let xmlString = String(data: data, encoding: .utf8) else {
            // No encryption.xml at all → not DRM'd.
            return false
        }

        // Adobe's algorithm namespace appears inside the EncryptionMethod
        // element. We don't need to parse the XML — a substring check is
        // enough and survives whitespace/attribute-order variations that
        // an XML parser would otherwise need to handle.
        return xmlString.lowercased().contains("adobe.com/adept")
    }
}
