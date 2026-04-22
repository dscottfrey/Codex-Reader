//
//  DuplicateChecker.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The matching logic that decides whether an incoming epub is the same
//  book as one already in the library. Defined in Module 2 (Ingestion
//  Engine) §5.2.
//
//  WHY THE THREE-CASE SHAPE:
//  The directive distinguishes:
//    A. Exact file match (same SHA-256) — definitely the same file.
//    B. Same title+author, different hash, recently read — probably the
//       same book, edited since.
//    C. Same title+author, different hash, NOT recently read — probably
//       a different edition.
//  We do those three cases as the `MatchKind` enum so the UI prompt can
//  branch cleanly on the result.
//

import Foundation
import SwiftData

/// What kind of duplicate (if any) was detected.
enum DuplicateMatch {

    /// No match — this is a brand-new book.
    case none

    /// Exact file match: same SHA-256. The existing record is `existing`.
    case exactFile(existing: Book)

    /// Same title + author, different hash, opened within the recency
    /// threshold. Probably the same book edited.
    case sameMetadataRecent(existing: Book)

    /// Same title + author, different hash, NOT opened recently. Probably
    /// a different edition.
    case sameMetadataOld(existing: Book)
}

/// Encapsulates the duplicate-detection rules.
@MainActor
struct DuplicateChecker {

    /// How recently is "recently read"? Default 30 days per directive
    /// §5.2. Configurable in Advanced Settings later.
    let recencyThreshold: TimeInterval

    init(recencyThreshold: TimeInterval = 60 * 60 * 24 * 30) {
        self.recencyThreshold = recencyThreshold
    }

    /// Look for a duplicate of an incoming book in the model context.
    ///
    /// - Parameters:
    ///   - title: Title from the incoming epub.
    ///   - author: Author from the incoming epub.
    ///   - sha256: SHA-256 of the incoming file. Used for the exact-match
    ///     branch.
    ///   - context: SwiftData model context to search in.
    /// - Returns: A `DuplicateMatch` value the caller can branch on.
    func check(
        title: String,
        author: String,
        sha256: String?,
        in context: ModelContext
    ) -> DuplicateMatch {

        // Exact-file match takes precedence — same hash = same file.
        if let sha = sha256, !sha.isEmpty,
           let exact = fetchOne(predicate: #Predicate<Book> { $0.fileSHA256 == sha }, in: context) {
            return .exactFile(existing: exact)
        }

        // Title+author match. We do a case-insensitive compare via a
        // local Swift filter rather than a Predicate because Predicate's
        // string handling is more limited.
        let descriptor = FetchDescriptor<Book>()
        let all = (try? context.fetch(descriptor)) ?? []
        let candidates = all.filter {
            $0.title.caseInsensitiveCompare(title) == .orderedSame &&
            $0.author.caseInsensitiveCompare(author) == .orderedSame
        }
        guard let match = candidates.first else { return .none }

        // Recency split.
        if let last = match.lastReadDate,
           Date().timeIntervalSince(last) < recencyThreshold {
            return .sameMetadataRecent(existing: match)
        } else {
            return .sameMetadataOld(existing: match)
        }
    }

    /// Convenience: return the first match for a Predicate, or nil.
    private func fetchOne(
        predicate: Predicate<Book>,
        in context: ModelContext
    ) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
