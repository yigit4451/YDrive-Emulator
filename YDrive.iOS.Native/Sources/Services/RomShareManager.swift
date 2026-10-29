import SwiftUI
import UIKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Zip Archiver (Pure Swift + zlib)
// ─────────────────────────────────────────────────────────────────────────────

/// Creates standard PKWARE .zip archives from one or more files using zlib Deflate compression.
enum ZipArchiver {

    private struct Entry {
        let relativePath: String
        let compressionMethod: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    /// Compresses data using raw DEFLATE (windowBits = -15). Returns nil if compression fails.
    private static func deflateData(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }

        var stream = z_stream()
        // -MAX_WBITS (-15) produces raw DEFLATE without zlib headers, as required by the ZIP specification.
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        input.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBuffer.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)

            while stream.avail_in > 0 {
                buffer.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(bufferSize)
                    deflate(&stream, Z_NO_FLUSH)
                    let written = bufferSize - Int(stream.avail_out)
                    if written > 0 {
                        output.append(outBuf.baseAddress!, count: written)
                    }
                }
            }

            var flushStatus = Z_OK
            while flushStatus != Z_STREAM_END {
                buffer.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(bufferSize)
                    flushStatus = deflate(&stream, Z_FINISH)
                    let written = bufferSize - Int(stream.avail_out)
                    if written > 0 {
                        output.append(outBuf.baseAddress!, count: written)
                    }
                }
            }
        }

        return output
    }

    /// Converts a Foundation Date to MS-DOS 16-bit time and date formats.
    private static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(max(1980, comps.year ?? 1980) - 1980)
        let month = UInt16(comps.month ?? 1)
        let day = UInt16(comps.day ?? 1)
        let hour = UInt16(comps.hour ?? 0)
        let minute = UInt16(comps.minute ?? 0)
        let second = UInt16((comps.second ?? 0) / 2)

        let dosTime = (hour << 11) | (minute << 5) | second
        let dosDate = (year << 9) | (month << 5) | day
        return (dosTime, dosDate)
    }

    /// Archives `files` into a .zip file at `destinationURL`.
    static func createZip(from files: [(url: URL, relativePath: String)], to destinationURL: URL) throws {
        var zipData = Data()
        var entries: [Entry] = []

        let now = Date()
        let (dosTime, dosDate) = dosDateTime(from: now)

        for item in files {
            let fileData = try Data(contentsOf: item.url)
            let uncompressedSize = UInt32(fileData.count)

            // Compute standard CRC32
            let crcValue: UInt32 = fileData.withUnsafeBytes { raw in
                if let base = raw.bindMemory(to: Bytef.self).baseAddress {
                    return UInt32(crc32(0, base, uInt(fileData.count)))
                }
                return 0
            }

            // Deflate compression
            let (compressionMethod, dataToWrite): (UInt16, Data) = {
                if let deflated = deflateData(fileData), deflated.count < fileData.count {
                    return (8 /* Deflate */, deflated)
                } else {
                    return (0 /* Stored */, fileData)
                }
            }()

            let compressedSize = UInt32(dataToWrite.count)
            let pathData = Data(item.relativePath.utf8)
            let localHeaderOffset = UInt32(zipData.count)

            // ── Local File Header ──
            zipData.appendLE(UInt32(0x04034b50))       // Signature
            zipData.appendLE(UInt16(20))               // Version needed (2.0)
            zipData.appendLE(UInt16(0x0800))           // Bit 11 = UTF-8 filename
            zipData.appendLE(compressionMethod)        // Compression method
            zipData.appendLE(dosTime)                  // Last mod time
            zipData.appendLE(dosDate)                  // Last mod date
            zipData.appendLE(crcValue)                 // CRC-32
            zipData.appendLE(compressedSize)           // Compressed size
            zipData.appendLE(uncompressedSize)         // Uncompressed size
            zipData.appendLE(UInt16(pathData.count))   // File name length
            zipData.appendLE(UInt16(0))                // Extra field length
            zipData.append(pathData)                   // File name
            zipData.append(dataToWrite)                // File data

            entries.append(Entry(
                relativePath: item.relativePath,
                compressionMethod: compressionMethod,
                dosTime: dosTime,
                dosDate: dosDate,
                crc: crcValue,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
        }

        // ── Central Directory ──
        let cdOffset = UInt32(zipData.count)
        var cdData = Data()

        for entry in entries {
            let pathData = Data(entry.relativePath.utf8)
            cdData.appendLE(UInt32(0x02014b50))       // Signature
            cdData.appendLE(UInt16(20))               // Version made by (2.0)
            cdData.appendLE(UInt16(20))               // Version needed (2.0)
            cdData.appendLE(UInt16(0x0800))           // Bit 11 = UTF-8
            cdData.appendLE(entry.compressionMethod)  // Compression method
            cdData.appendLE(entry.dosTime)            // Last mod time
            cdData.appendLE(entry.dosDate)            // Last mod date
            cdData.appendLE(entry.crc)                // CRC-32
            cdData.appendLE(entry.compressedSize)     // Compressed size
            cdData.appendLE(entry.uncompressedSize)   // Uncompressed size
            cdData.appendLE(UInt16(pathData.count))   // File name length
            cdData.appendLE(UInt16(0))                // Extra field length
            cdData.appendLE(UInt16(0))                // File comment length
            cdData.appendLE(UInt16(0))                // Disk number start
            cdData.appendLE(UInt16(0))                // Internal file attributes
            cdData.appendLE(UInt32(0))                // External file attributes
            cdData.appendLE(entry.localHeaderOffset)  // Relative offset of local header
            cdData.append(pathData)                   // File name
        }

        zipData.append(cdData)

        // ── End of Central Directory Record ──
        zipData.appendLE(UInt32(0x06054b50))          // Signature
        zipData.appendLE(UInt16(0))                   // Number of this disk
        zipData.appendLE(UInt16(0))                   // Disk with start of CD
        zipData.appendLE(UInt16(entries.count))       // Number of entries on this disk
        zipData.appendLE(UInt16(entries.count))       // Total entries
        zipData.appendLE(UInt32(cdData.count))        // Size of CD
        zipData.appendLE(cdOffset)                    // Offset of start of CD
        zipData.appendLE(UInt16(0))                   // Comment length

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try zipData.write(to: destinationURL, options: .atomic)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Rom Share Manager
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class RomShareManager: ObservableObject {
    static let shared = RomShareManager()

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Published var shareItem: ShareItem?
    @Published var isArchiving: Bool = false

    /// Cleans special characters from title to create a safe filename.
    private func sanitizeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = title.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ROM" : trimmed
    }

    /// Prepares a .zip archive of the given game and sets `shareItem` to trigger the iOS share sheet.
    func share(game: GameItem) {
        let primaryURL = URL(fileURLWithPath: game.fileName)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            print("[RomShareManager] Game file not found at \(primaryURL.path)")
            return
        }

        let cleanTitle = sanitizeFileName(game.title)
        let tempDir = FileManager.default.temporaryDirectory
        let targetZipURL = tempDir.appendingPathComponent("\(cleanTitle).zip")

        // If the game file is already a .zip archive, share it directly or copy as <Title>.zip
        if primaryURL.pathExtension.lowercased() == "zip" {
            do {
                if FileManager.default.fileExists(atPath: targetZipURL.path) {
                    try? FileManager.default.removeItem(at: targetZipURL)
                }
                try FileManager.default.copyItem(at: primaryURL, to: targetZipURL)
                self.shareItem = ShareItem(url: targetZipURL)
            } catch {
                // Fallback to sharing original zip URL directly
                self.shareItem = ShareItem(url: primaryURL)
            }
            return
        }

        isArchiving = true

        Task.detached(priority: .userInitiated) {
            let folderURL = primaryURL.deletingLastPathComponent()
            var filesToArchive: [(url: URL, relativePath: String)] = []

            // If the game resides in a dedicated subfolder under ROM's (e.g. for multi-track CD games),
            // include all relevant ROM files (.cue, .bin, .iso, etc.) in that folder.
            if folderURL.lastPathComponent != "ROM's" && folderURL.path.contains("ROM's") {
                let romExtensions = Set(["md", "bin", "gen", "smd", "zip", "chd", "32x", "sms", "gg", "iso", "cue"])
                if let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for file in contents {
                        if romExtensions.contains(file.pathExtension.lowercased()) {
                            filesToArchive.append((url: file, relativePath: file.lastPathComponent))
                        }
                    }
                }
            }

            // Fallback: archive the single ROM file
            if filesToArchive.isEmpty {
                filesToArchive.append((url: primaryURL, relativePath: primaryURL.lastPathComponent))
            }

            do {
                try ZipArchiver.createZip(from: filesToArchive, to: targetZipURL)
                await MainActor.run {
                    self.isArchiving = false
                    self.shareItem = ShareItem(url: targetZipURL)
                }
            } catch {
                print("[RomShareManager] Failed to create zip: \(error)")
                await MainActor.run {
                    self.isArchiving = false
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Activity View Controller (iOS Share Sheet)
// ─────────────────────────────────────────────────────────────────────────────

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
