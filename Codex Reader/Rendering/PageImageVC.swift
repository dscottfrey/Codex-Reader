//
//  PageImageVC.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A minimal UIViewController that displays one pre-rendered page as a
//  UIImage. Replaces `ChapterPageVC` for paginated modes (Curl/Slide).
//  Each instance corresponds to one page index of one chapter; its
//  image is pulled from `PageImageCache` either at creation time or
//  when a "page rendered" notification arrives.
//
//  WHY SO SMALL:
//  All the heavy lifting — opening the chapter, applying user
//  typography CSS, measuring CSS Columns, snapshotting columns to
//  UIImages — happens upstream in `ChapterPageRenderer`. By the time
//  this VC is created, the work is either already done (cache hit) or
//  in flight (cache miss → placeholder background until the
//  notification fires). The VC's only job is "show this UIImage at
//  full size."
//
//  WHY NO JS BRIDGE:
//  ChapterPageVC owned a live WKWebView and a JS message handler so
//  PaginationJS could report pageCount and snap-confirmation events
//  back. PageImageVC has no WKWebView and no JS — pages are static
//  images. Page-changed events come from the UIPageViewController
//  delegate (in `PaginatedChapterView.Coordinator`), not from JS.
//
//  ACCESSIBILITY:
//  The image view itself is marked `isAccessibilityElement = false`.
//  Per Rendering directive §6, accessibility (VoiceOver) is not a v1
//  goal; future work will add a WKWebView interaction layer behind
//  the image view (Milestone C / directive §3.6) which becomes the
//  semantic source. For now the image is opaque to assistive tech.
//

import UIKit

/// Hosts a single UIImageView showing one pre-rendered page of a
/// chapter. Lifetime is one page-turn worth: UIPageViewController
/// keeps ~3 alive (current/prev/next) and discards the rest.
final class PageImageVC: UIViewController {

    /// Chapter href this page belongs to. Same string the cache and
    /// the spine use as the canonical chapter identifier.
    let chapterHref: String

    /// 1-based page index, matching PaginationJS / cache convention.
    let pageIndex: Int

    /// The image view. Public read-only so the coordinator can
    /// override `image` directly when a deferred render lands.
    private(set) var imageView: UIImageView!

    /// The displayed image. Setting this from the coordinator (after a
    /// late render) updates the screen synchronously — UIImageView
    /// invalidates and redraws on assignment.
    var pageImage: UIImage? {
        get { imageView?.image }
        set { imageView?.image = newValue }
    }

    init(chapterHref: String, pageIndex: Int, initialImage: UIImage?) {
        self.chapterHref = chapterHref
        self.pageIndex = pageIndex
        super.init(nibName: nil, bundle: nil)
        // Initial image is set in viewDidLoad once the view exists.
        // Stash it in a property until then.
        self.pendingInitialImage = initialImage
    }

    required init?(coder: NSCoder) {
        fatalError("PageImageVC is created programmatically only.")
    }

    private var pendingInitialImage: UIImage?

    override func loadView() {
        // Build the image view as the VC's root view. .scaleAspectFit
        // preserves the rendered geometry — the renderer matched its
        // off-screen WebView frame to the on-screen reading area, so
        // the UIImage already has the right aspect ratio at @2x. fit
        // (vs fill) avoids cropping when something rounds slightly off.
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isAccessibilityElement = false
        iv.backgroundColor = .clear
        self.imageView = iv
        self.view = iv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let pendingInitialImage {
            imageView.image = pendingInitialImage
            self.pendingInitialImage = nil
        }
    }
}
