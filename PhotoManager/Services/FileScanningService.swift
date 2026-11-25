import Foundation
import ImageIO
import AVFoundation
import CryptoKit
import os.log

/// Walks a root directory and keeps the catalogue in step with it.
///
/// Incremental: a file whose size and modification date are unchanged is skipped; a changed file is
/// updated in place (so its rating, tags and event survive); files that have disappeared are removed.
/// `fullRescan` re-hashes everything but still never touches user data.
final class FileScanningService {
    private let databaseManager: DatabaseManager
    private static let logger = Logger(subsystem: "com.photomarger", category: "scanning")

    struct Progress {
        var phase: String
        var completed: Int
        var total: Int
        var currentFile: String
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    struct Summary {
        var found = 0
        var unchanged = 0
        var added = 0
        var updated = 0
        var removed = 0
        var failed = 0
    }

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    @discardableResult
    func scanDirectory(_ rootDirectory: RootDirectory, fullRescan: Bool = false,
                       progress: @escaping (Progress) -> Void = { _ in }) async throws -> Summary {
        guard let rootId = rootDirectory.id else { throw FileScanningError.invalidRootDirectory }

        return try await SecurityScope.withAccess(rootDirectory) {
            var summary = Summary()
            let rootPath = (rootDirectory.path as NSString).standardizingPath

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                // An unmounted drive must not look like "every file was deleted".
                throw FileScanningError.rootUnavailable(rootPath)
            }

            progress(Progress(phase: "Listing files", completed: 0, total: 0, currentFile: ""))
            let listing = try Self.listMediaFiles(in: rootPath)
            summary.found = listing.files.count

            let index = try databaseManager.scanIndex(rootId: rootId)
            var toProcess: [ListedFile] = []
            for file in listing.files {
                if !fullRescan, let existing = index[file.relativePath],
                   existing.fileSize == file.size,
                   abs(existing.modifiedAt - file.modified.timeIntervalSince1970) < 1 {
                    summary.unchanged += 1
                } else {
                    toProcess.append(file)
                }
            }

            let total = toProcess.count
            var completed = 0
            var buffer: [ScannedFile] = []
            var lastReport = Date.distantPast
            let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)

            try await withThrowingTaskGroup(of: ScannedFile?.self) { group in
                var iterator = toProcess.makeIterator()
                func enqueue() {
                    guard let file = iterator.next() else { return }
                    group.addTask(priority: .utility) {
                        do { return try await Self.processFile(file, rootId: rootId) }
                        catch {
                            Self.logger.error("Failed \(file.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            return nil
                        }
                    }
                }
                for _ in 0..<workers { enqueue() }

                while let result = try await group.next() {
                    try Task.checkCancellation()
                    completed += 1
                    if let scanned = result {
                        if index[scanned.relativePath] == nil { summary.added += 1 } else { summary.updated += 1 }
                        buffer.append(scanned)
                    } else {
                        summary.failed += 1
                    }
                    if buffer.count >= 500 {
                        try databaseManager.upsert(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                    if Date().timeIntervalSince(lastReport) > 0.2 {
                        lastReport = Date()
                        progress(Progress(phase: "Reading files", completed: completed, total: total,
                                          currentFile: result?.fileName ?? ""))
                    }
                    enqueue()
                }
            }
            try databaseManager.upsert(buffer)

            // Remove rows for files that are gone, but only after a clean, complete listing.
            if listing.hadErrors {
                Self.logger.warning("Directory listing reported errors; not removing missing files this time")
            } else {
                let present = Set(listing.files.map(\.relativePath))
                let missing = index.filter { !present.contains($0.key) }.map(\.value.id)
                if !missing.isEmpty {
                    let orphaned = try databaseManager.deletePhotos(ids: missing)
                    ThumbnailService.deleteThumbnails(forHashes: orphaned)
                    summary.removed = missing.count
                }
            }

            try databaseManager.updateRootDirectoryLastScanned(rootId, date: Date())
            progress(Progress(phase: "Done", completed: total, total: total, currentFile: ""))
            Self.logger.info("Scan of \(rootPath, privacy: .public): \(summary.found) found, \(summary.added) added, \(summary.updated) updated, \(summary.removed) removed, \(summary.failed) failed")
            return summary
        }
    }

    // MARK: - Listing

    struct ListedFile {
        let path: String
        let relativePath: String
        let size: Int64
        let modified: Date
        let created: Date
        let kind: MediaKind
    }

    static func listMediaFiles(in rootPath: String) throws -> (files: [ListedFile], hadErrors: Bool) {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        var hadErrors = false
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                logger.warning("Cannot read \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                hadErrors = true
                return true
            }) else {
            throw FileScanningError.fileNotFound
        }

        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var files: [ListedFile] = []
        for case let url as URL in enumerator {
            guard let kind = MediaKind(fileExtension: url.pathExtension),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let path = url.path
            // Paths from the enumerator can differ from rootPath in /private or symlink prefixes.
            let relative: String
            if path.hasPrefix(prefix) {
                relative = String(path.dropFirst(prefix.count))
            } else if let range = path.range(of: "/" + rootURL.lastPathComponent + "/") {
                relative = String(path[range.upperBound...])
            } else {
                relative = url.lastPathComponent
            }
            files.append(ListedFile(path: path, relativePath: relative, size: Int64(values.fileSize ?? 0),
                                    modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                                    created: values.creationDate ?? values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                                    kind: kind))
        }
        return (files, hadErrors)
    }

    // MARK: - Per-file work

    static func processFile(_ file: ListedFile, rootId: Int64) async throws -> ScannedFile {
        let hash = try hashFile(atPath: file.path)
        let meta: MediaMetadata
        if file.kind == .video {
            meta = await videoMetadata(URL(fileURLWithPath: file.path))
        } else {
            meta = imageMetadata(URL(fileURLWithPath: file.path))
        }

        let fileName = (file.relativePath as NSString).lastPathComponent
        let capture: (Date, DateSource)
        if let date = meta.captureDate {
            capture = (date, file.kind == .video ? .video : .exif)
        } else if let date = dateFromFilename(fileName) {
            capture = (date, .filename)
        } else {
            capture = (meta.fallbackDate ?? file.modified, .file)
        }

        return ScannedFile(
            rootDirectoryId: rootId, relativePath: file.relativePath, fileName: fileName,
            fileExtension: (fileName as NSString).pathExtension.lowercased(), mediaKind: file.kind,
            fileSize: file.size, fileHash: hash, createdAt: file.created, modifiedAt: file.modified,
            exifDateTaken: file.kind == .video ? nil : meta.captureDate,
            captureDate: capture.0, dateSource: capture.1,
            cameraModel: meta.cameraModel, lensModel: meta.lensModel, focalLength: meta.focalLength,
            aperture: meta.aperture, iso: meta.iso, shutterSpeed: meta.shutterSpeed,
            imageWidth: meta.width, imageHeight: meta.height,
            gpsLatitude: meta.latitude, gpsLongitude: meta.longitude,
            contentIdentifier: meta.contentIdentifier, duration: meta.duration)
    }

    /// SHA-256 of the file, read in chunks so large RAW and video files don't load into memory.
    static func hashFile(atPath path: String) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw FileScanningError.fileNotFound }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 4 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    struct MediaMetadata {
        var captureDate: Date?
        var fallbackDate: Date?      // e.g. TIFF DateTime: when software last wrote the file
        var cameraModel: String?
        var lensModel: String?
        var focalLength: Double?
        var aperture: Double?
        var iso: Int?
        var shutterSpeed: String?
        var width: Int?
        var height: Int?
        var latitude: Double?
        var longitude: Double?
        var contentIdentifier: String?
        var duration: Double?
    }

    static func imageMetadata(_ url: URL) -> MediaMetadata {
        var meta = MediaMetadata()
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            return meta
        }
        meta.width = props[kCGImagePropertyPixelWidth] as? Int
        meta.height = props[kCGImagePropertyPixelHeight] as? Int

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            let digitized = exif[kCGImagePropertyExifDateTimeDigitized] as? String
            meta.captureDate = (original ?? digitized).flatMap(parseExifDate)
            meta.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            meta.aperture = exif[kCGImagePropertyExifFNumber] as? Double
            meta.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
                meta.shutterSpeed = exposure >= 1 ? String(format: "%.1fs", exposure) : "1/\(Int((1 / exposure).rounded()))s"
            }
            meta.lensModel = exif[kCGImagePropertyExifLensModel] as? String
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
            let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
            if let model {
                // Many cameras already include the make in the model ("Canon EOS R5").
                if let make, !model.lowercased().hasPrefix(make.lowercased().split(separator: " ").first.map(String.init) ?? make.lowercased()) {
                    meta.cameraModel = "\(make) \(model)"
                } else {
                    meta.cameraModel = model
                }
            }
            meta.fallbackDate = (tiff[kCGImagePropertyTIFFDateTime] as? String).flatMap(parseExifDate)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
           !(lat == 0 && lon == 0) {
            meta.latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
            meta.longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
        }
        // Live Photo still: the paired video carries the same content identifier.
        if let apple = props[kCGImagePropertyMakerAppleDictionary] as? [String: Any] {
            meta.contentIdentifier = apple["17"] as? String
        }
        return meta
    }

    static func videoMetadata(_ url: URL) async -> MediaMetadata {
        var meta = MediaMetadata()
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return meta }
        if let duration = try? await asset.load(.duration) {
            meta.duration = duration.seconds.isFinite ? duration.seconds : nil
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize) {
            meta.width = Int(abs(size.width))
            meta.height = Int(abs(size.height))
        }
        for item in items {
            guard let key = item.identifier?.rawValue else { continue }
            switch key {
            case "mdta/com.apple.quicktime.creationdate":
                if let text = try? await item.load(.stringValue) { meta.captureDate = parseQuickTimeDate(text) }
            case "mdta/com.apple.quicktime.location.ISO6709", "udta/©xyz":
                if let text = try? await item.load(.stringValue), let (lat, lon) = parseISO6709(text) {
                    meta.latitude = lat
                    meta.longitude = lon
                }
            case "mdta/com.apple.quicktime.model":
                meta.cameraModel = try? await item.load(.stringValue)
            case "mdta/com.apple.quicktime.content.identifier":
                meta.contentIdentifier = try? await item.load(.stringValue)
            default:
                break
            }
        }
        if meta.captureDate == nil, let created = try? await asset.load(.creationDate),
           let date = try? await created.load(.dateValue) {
            meta.captureDate = date
        }
        return meta
    }

    // MARK: - Date parsing

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    /// EXIF dates are wall-clock time with no zone; read them in the current zone so they display as shot.
    static func parseExifDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard trimmed.count >= 19, !trimmed.hasPrefix("0000") else { return nil }
        return exifFormatter.date(from: String(trimmed.prefix(19)))
    }

    /// QuickTime creation dates carry their own offset ("2019-03-12T10:15:02+0800"). Keep the wall-clock
    /// time where the video was shot and reinterpret it in the current zone, matching how EXIF is read.
    static func parseQuickTimeDate(_ text: String) -> Date? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})"#
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            return ISO8601DateFormatter().date(from: text)
        }
        let wallClock = String(text[match]).replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "-", with: ":")
        return parseExifDate(wallClock)
    }

    static func parseISO6709(_ text: String) -> (Double, Double)? {
        let pattern = #"([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let latRange = Range(m.range(at: 1), in: text), let lonRange = Range(m.range(at: 2), in: text),
              let lat = Double(text[latRange]), let lon = Double(text[lonRange]) else { return nil }
        return (lat, lon)
    }

    private static let filenameDateRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)((?:19|20)\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])(?:[-_ T]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d))?(?!\d)"#)

    /// Dates embedded in names like IMG_20190312_101502.jpg, 2019-03-12 10.15.02.jpg or Scan_19980704.tif.
    static func dateFromFilename(_ name: String) -> Date? {
        let range = NSRange(name.startIndex..., in: name)
        guard let m = filenameDateRegex.firstMatch(in: name, range: range) else { return nil }
        func part(_ i: Int) -> Int? {
            guard let r = Range(m.range(at: i), in: name) else { return nil }
            return Int(name[r])
        }
        var components = DateComponents()
        components.year = part(1)
        components.month = part(2)
        components.day = part(3)
        components.hour = part(4) ?? 12
        components.minute = part(5) ?? 0
        components.second = part(6) ?? 0
        guard let date = Calendar.current.date(from: components), date < Date().addingTimeInterval(86400) else { return nil }
        return date
    }
}

enum FileScanningError: Error, LocalizedError {
    case invalidRootDirectory
    case fileNotFound
    case hashCalculationFailed
    case rootUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidRootDirectory: return "Root directory has no id"
        case .fileNotFound: return "File not found"
        case .hashCalculationFailed: return "Could not hash file"
        case .rootUnavailable(let path): return "\(path) is not available (is the drive connected?)"
        }
    }
}
