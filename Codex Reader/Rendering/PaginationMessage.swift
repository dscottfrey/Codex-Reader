//
//  PaginationMessage.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The typed Swift representation of the JS → Swift messages posted
//  by PaginationJS. The coordinator in WKWebViewWrapper decodes raw
//  `WKScriptMessage` bodies into one of these cases and hands them to
//  the view model.
//
//  WHY IT'S AN ENUM, NOT A STRUCT:
//  The JS posts messages of three distinct shapes (a pagination
//  report, a page-change confirmation, a scroll-progress tick). An
//  enum makes the "exactly one of these" nature of each message
//  explicit and forces exhaustive handling downstream.
//
//  DECODING:
//  WKScriptMessage bodies come through as Foundation types (NSDictionary,
//  NSNumber, NSString). We read them defensively — a missing or
//  wrong-typed field produces nil, and the coordinator drops the
//  message. Better to ignore a malformed tick than to crash mid-page.
//

import Foundation

/// One message from the PaginationJS bridge.
enum PaginationMessage {

    /// JS has finished (re-)measuring the chapter. `total` and
    /// `current` are 1-based page counts when paginated == true; in
    /// scroll mode both come through as 1.
    case pagination(total: Int, current: Int, paginated: Bool)

    /// JS has completed a page turn (either from `codexGoToPage` or
    /// from `codexNextPage` / `codexPrevPage`).
    case pageChanged(current: Int)

    /// Scroll-mode progress tick — 0.0 at top of chapter, 1.0 at
    /// bottom.
    case scrollProgress(progress: Double)

    /// Decode a raw message body. Returns nil for anything we don't
    /// recognise — the coordinator silently drops unknown messages.
    init?(from body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String
        else { return nil }

        switch type {
        case "pagination":
            guard let total = (dict["totalPages"] as? NSNumber)?.intValue,
                  let current = (dict["currentPage"] as? NSNumber)?.intValue
            else { return nil }
            let paginated = (dict["paginated"] as? NSNumber)?.boolValue ?? true
            self = .pagination(
                total: total,
                current: current,
                paginated: paginated
            )

        case "pageChanged":
            guard let current = (dict["currentPage"] as? NSNumber)?.intValue
            else { return nil }
            self = .pageChanged(current: current)

        case "scrollProgress":
            guard let progress = (dict["progress"] as? NSNumber)?.doubleValue
            else { return nil }
            self = .scrollProgress(progress: progress)

        default:
            return nil
        }
    }
}
