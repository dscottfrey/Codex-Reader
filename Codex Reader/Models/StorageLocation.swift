//
//  StorageLocation.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  Where a single book's epub file actually lives on disk. Defined by the
//  Ingestion Engine directive (§8.1) as the foundation of "Codex never
//  holds a book hostage to iCloud."
//
//  WHY IT EXISTS:
//  Every Book record needs to know whether to look in iCloud Drive or in
//  Application Support. Promoting a book from `.localOnly` back to
//  `.iCloudDrive` (or vice versa) is the user-facing "Keep Local Only" /
//  "Upload to iCloud" feature. Storing this on the Book record means the
//  decision is per-book, not global.
//

import Foundation

/// Where the epub file is physically stored.
///
/// `.iCloudDrive` is the normal state — the file lives in
/// `iCloud Drive/Codex/Library/`, visible to the user in the Files app,
/// and synced across devices automatically by iOS.
///
/// `.localOnly` is the fallback for when iCloud is being difficult — the
/// file has been moved to the app's Application Support directory and is
/// readable without iCloud being involved.
enum StorageLocation: String, Codable {
    case iCloudDrive
    case localOnly
}

/// The richer "what is happening with this file in iCloud right now"
/// state, derived from `URLResourceKey` attributes by the iCloud monitor.
/// Library Manager directive §6.5 lists the icons each maps to.
///
/// `.localOnly` here means the same thing as `StorageLocation.localOnly`
/// — the book has been deliberately moved out of iCloud Drive — and
/// `.missing` means no copy exists anywhere (a "ghost record").
enum ICloudFileState: String, Codable {
    case synced
    case uploading
    case uploadError
    case cloudOnly
    case downloading
    case downloadError
    case localOnly
    case missing
}
