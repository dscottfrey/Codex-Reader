//
//  PageTurnStyle.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The three page-turn styles a reader can choose. Defined in Module 1
//  (Rendering Engine) §2.5.
//
//  WHY IT EXISTS:
//  Each style maps to a different rendering path. The renderer asks
//  "which style?" and chooses between UIPageViewController.pageCurl,
//  UIPageViewController.scroll, or a free-scrolling WKWebView. Keeping
//  the enum small and standalone means anywhere in the app can speak about
//  page-turn style without pulling in renderer code.
//
//  NOT INCLUDED:
//  "Fade" was considered and dropped — see directive §2.5. Adding it later
//  would mean adding a case here AND a rendering path; we chose not to.
//

import Foundation

/// The page transition styles supported by the reader.
///
/// All three are either free Apple APIs or the WebView's natural behaviour,
/// per the directive: no custom animation code is required.
enum PageTurnStyle: String, Codable, CaseIterable, Identifiable {

    /// Skeuomorphic paper curl — finger follows the page edge. Implemented
    /// with `UIPageViewController(transitionStyle: .pageCurl)`.
    case curl

    /// Horizontal slide — page follows finger, snaps past midpoint.
    /// Implemented with `UIPageViewController(transitionStyle: .scroll)`.
    /// "Slide" and "Swipe" are the same gesture; we use one name.
    case slide

    /// Continuous vertical scroll — no page breaks, no pagination. The
    /// WKWebView's default behaviour.
    case scroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl:   return "Page Curl"
        case .slide:  return "Slide"
        case .scroll: return "Scroll"
        }
    }
}
