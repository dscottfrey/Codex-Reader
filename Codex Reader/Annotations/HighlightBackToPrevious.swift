//
//  HighlightBackToPrevious.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The "Highlight Back to Previous" operation — given a tapped end
//  highlight, find the nearest prior highlight in the same chapter and
//  merge the two into a single span. Defined in Module 6 (Annotation
//  System) §3.3 and Module 5 §4.2.
//
//  WHY ITS OWN FILE:
//  This is a non-trivial annotation operation that touches the store
//  in a specific sequence (find prior, validate, create the merged
//  highlight, soft-delete both anchors). Pulling it out keeps the
//  AnnotationStore focused on simple CRUD.
//
//  THE CHAPTER-BOUNDARY RULE:
//  Per directive: highlights are chapter-scoped. If the nearest prior
//  highlight is in a different chapter, the operation isn't valid.
//  Callers should hide the "Highlight Back to Previous" menu item when
//  `validate(...)` returns nil.
//

import Foundation
import SwiftData

@MainActor
struct HighlightBackToPrevious {

    let store: AnnotationStore

    /// Look for the nearest prior highlight in the same chapter. Returns
    /// nil when none exists, or when the call wouldn't make sense (e.g.,
    /// the tapped annotation isn't a highlight). The UI uses this to
    /// decide whether to even show the menu item.
    func validate(tappedAnnotation: Annotation) -> Annotation? {
        guard tappedAnnotation.type == .highlight else { return nil }

        let chapterAnnotations = store.annotations(
            forBookID: tappedAnnotation.bookID,
            chapterHref: tappedAnnotation.chapterHref
        )
        // Prior = immediately preceding by startOffset within the same chapter.
        let priors = chapterAnnotations.filter {
            $0.id != tappedAnnotation.id &&
            $0.type == .highlight &&
            $0.endOffset < tappedAnnotation.startOffset
        }
        return priors.last  // store sorts by startOffset; last is closest
    }

    /// Apply the merge — soft-delete the two anchor highlights, create
    /// a new merged highlight spanning from the prior's start to the
    /// tapped annotation's end. Returns the new highlight.
    @discardableResult
    func apply(tappedAnnotation: Annotation) -> Annotation? {
        guard let prior = validate(tappedAnnotation: tappedAnnotation) else { return nil }

        let merged = store.addHighlight(
            bookID: tappedAnnotation.bookID,
            chapterHref: tappedAnnotation.chapterHref,
            startOffset: prior.startOffset,
            endOffset: tappedAnnotation.endOffset,
            color: tappedAnnotation.highlightColor ?? .yellow
        )

        // Absorb the two anchors per directive §3.3: "the two anchor
        // highlights are absorbed into the larger one." We soft-delete
        // them so the deletion syncs to other devices.
        store.softDelete(prior)
        store.softDelete(tappedAnnotation)

        return merged
    }
}
