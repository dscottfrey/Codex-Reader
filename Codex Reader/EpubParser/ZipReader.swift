//
//  ZipReader.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  A tiny, focused ZIP central-directory reader. It takes the bytes of
//  a ZIP file (an epub) and hands back the list of entries plus the
//  uncompressed bytes of any single entry. Internal to EpubArchive.swift
//  — not used directly anywhere else.
//
//  WHY IT EXISTS:
//  See the file header comment in EpubArchive.swift. The directive's
//  literal `Process()/unzip` approach doesn't work on iOS, so we read
//  the ZIP format directly using Foundation's `Compression` framework
//  for the one compression method epubs actually use (DEFLATE).
//
//  WHAT IT DOES NOT HANDLE:
//  - ZIP64 (archives over 4 GB or with more than 65,535 entries). Out
//    of scope — no real epub needs 4 GB.
//  - Encrypted ZIP entries. Epubs use DRM at the container level (the
//    Adobe ADEPT marker in META-INF/encryption.xml) rather than by
//    encrypting individual ZIP entries, and we refuse DRM'd epubs at
//    the ingestion gate anyway (§5.1).
//  - Anything other than Stored (method 0) and Deflate (method 8).
//    Store and Deflate cover essentially every real epub.
//
//  REFERENCE: APPNOTE.TXT v6.3.10 (PKWARE's canonical ZIP spec).
//

import Foundation
import Compression

/// One file listed in the ZIP central directory. Opaque to the rest of
/// the app — EpubArchive is the only consumer.
struct ZipEntry {
    let filename: String
    let compressionMethod: UInt16   // 0 = stored, 8 = deflate
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

enum ZipReaderError: Error {
    case noEndOfCentralDirectory
    case badCentralDirectory
    case badLocalHeader
    case unsupportedCompression(UInt16)
    case decompressionFailed
}

enum ZipReader {

    // ZIP signatures (little-endian 32-bit magic numbers).
    private static let eocdSignature:    UInt32 = 0x06054b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let localSignature:   UInt32 = 0x04034b50

    /// Walk the ZIP's central directory and return one descriptor per
    /// entry. The central directory lives at the end of the file — we
    /// search backwards for the End of Central Directory record, read
    /// the offset from it, then walk forward through the entries.
    static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        guard let eocdOffset = findEOCD(in: data) else {
            throw ZipReaderError.noEndOfCentralDirectory
        }

        // EOCD layout (starting at signature):
        //   0  signature      4
        //   4  diskNum        2
        //   6  cdDisk         2
        //   8  entriesOnDisk  2
        //  10  totalEntries   2
        //  12  cdSize         4
        //  16  cdOffset       4
        //  20  commentLen     2
        let totalEntries = data.readUInt16(at: eocdOffset + 10)
        let cdOffset     = Int(data.readUInt32(at: eocdOffset + 16))

        var entries: [ZipEntry] = []
        entries.reserveCapacity(Int(totalEntries))

        var cursor = cdOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  data.readUInt32(at: cursor) == centralSignature
            else { throw ZipReaderError.badCentralDirectory }

            // Central directory header layout (offsets from signature):
            //   0  signature           4
            //  10  compressionMethod   2
            //  20  compressedSize      4
            //  24  uncompressedSize    4
            //  28  filenameLength      2
            //  30  extraLength         2
            //  32  commentLength       2
            //  42  localHeaderOffset   4
            //  46  filename            [filenameLength]
            let method       = data.readUInt16(at: cursor + 10)
            let compSize     = data.readUInt32(at: cursor + 20)
            let uncompSize   = data.readUInt32(at: cursor + 24)
            let nameLen      = Int(data.readUInt16(at: cursor + 28))
            let extraLen     = Int(data.readUInt16(at: cursor + 30))
            let commentLen   = Int(data.readUInt16(at: cursor + 32))
            let localOffset  = data.readUInt32(at: cursor + 42)

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else {
                throw ZipReaderError.badCentralDirectory
            }
            let filename = String(
                data: data.subdata(in: nameStart..<nameEnd),
                encoding: .utf8
            ) ?? ""

            entries.append(ZipEntry(
                filename: filename,
                compressionMethod: method,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset
            ))

            cursor = nameEnd + extraLen + commentLen
        }

        return entries
    }

    /// Read and (if necessary) decompress the bytes of a single entry.
    static func readEntryData(_ entry: ZipEntry, from data: Data) throws -> Data {
        let headerOffset = Int(entry.localHeaderOffset)
        guard headerOffset + 30 <= data.count,
              data.readUInt32(at: headerOffset) == localSignature
        else { throw ZipReaderError.badLocalHeader }

        // Local file header layout:
        //   0  signature           4
        //  26  filenameLength      2
        //  28  extraLength         2
        //  30  filename + extra + data
        let nameLen  = Int(data.readUInt16(at: headerOffset + 26))
        let extraLen = Int(data.readUInt16(at: headerOffset + 28))
        let dataStart = headerOffset + 30 + nameLen + extraLen
        let dataEnd   = dataStart + Int(entry.compressedSize)
        guard dataEnd <= data.count else { throw ZipReaderError.badLocalHeader }

        let compressed = data.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0:   // Stored — no compression.
            return compressed
        case 8:   // Deflate.
            return try inflate(compressed, uncompressedSize: Int(entry.uncompressedSize))
        default:
            throw ZipReaderError.unsupportedCompression(entry.compressionMethod)
        }
    }

    // MARK: - Private helpers

    /// Locate the End of Central Directory record. Per the spec the EOCD
    /// is within the last 65,557 bytes (64 KB comment max + record size).
    /// We scan backwards from the end for the 4-byte signature.
    private static func findEOCD(in data: Data) -> Int? {
        let maxBack = min(data.count, 65_557)
        let start = data.count - maxBack
        var i = data.count - 22  // minimum EOCD size is 22 bytes
        while i >= start {
            if data.readUInt32(at: i) == eocdSignature { return i }
            i -= 1
        }
        return nil
    }

    /// Decompress a raw DEFLATE stream (no zlib or gzip wrapper) to a
    /// buffer of known uncompressed size. `COMPRESSION_ZLIB` in Apple's
    /// Compression framework is RFC 1951 raw DEFLATE, which is exactly
    /// what ZIP wraps entries in — no wrapper translation required.
    private static func inflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        // Empty entry — nothing to do.
        if uncompressedSize == 0 { return Data() }

        var destination = Data(count: uncompressedSize)
        let written: Int = destination.withUnsafeMutableBytes { destPtr in
            compressed.withUnsafeBytes { srcPtr in
                guard let destBase = destPtr.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destBase, uncompressedSize,
                    srcBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else {
            throw ZipReaderError.decompressionFailed
        }
        return destination
    }
}

// MARK: - Data helpers (little-endian integer reads)

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let lo = UInt16(self[offset])
        let hi = UInt16(self[offset + 1])
        return (hi << 8) | lo
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }
}
