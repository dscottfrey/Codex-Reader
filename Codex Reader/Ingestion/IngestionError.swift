//
//  IngestionError.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  All the user-visible failure modes of the ingestion pipeline. Defined
//  in Module 2 (Ingestion Engine) §6 / §9 — same table both places.
//
//  WHY ITS OWN FILE:
//  These messages are the user-facing voice of the ingestion module. By
//  keeping them in one enum (a) the wording stays consistent, (b)
//  localisation will be a single edit per language, (c) the pipeline can
//  throw a typed error and the UI can show the right message without
//  string handling in the middle.
//

import Foundation

/// A failure in the ingestion pipeline. The `userMessage` is the exact
/// text the directive specifies should be shown to the user.
enum IngestionError: Error, LocalizedError {

    case notValidEpub
    case zipContainsNoEpub
    case drmProtected
    case storageFull
    case duplicateDetected
    case downloadFailed
    case underlying(Error)

    /// Plain-English message for the user — matches the directive's
    /// table verbatim. Surfaces through SwiftUI's `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .notValidEpub:
            return "This file doesn't appear to be a valid epub and couldn't be added."
        case .zipContainsNoEpub:
            return "This archive doesn't contain any epub files."
        case .drmProtected:
            return "This epub is DRM-protected. Codex only supports DRM-free epub files."
        case .storageFull:
            return "Not enough storage to add this book."
        case .duplicateDetected:
            return "This book may already be in your library."
        case .downloadFailed:
            return "Download interrupted. Try again?"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}
