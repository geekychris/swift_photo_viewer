import Foundation
import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import os.log

/// Generates and stores thumbnails. Thumbnails are content-addressed (Thumbnails/ab/<sha256>.jpg),
/// so every copy of a photo shares one, and they survive rescans and moves.
final class ThumbnailService {
    private static let logger = Logger(subsystem: "com.photomarger", category: "thumbnails")
    private let databaseManager: DatabaseManager
    static let thumbnailSize: CGFloat = 400

    static let thumbnailDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PhotoManager/Thumbnails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    static func thumbnailURL(forHash hash: String) -> URL {
        let shard = String(hash.prefix(2))
        return thumbnailDirectory.appendingPathComponent(shard).appendingPathComponent("\(hash).jpg")
    }

    func generateThumbnailsForDirectory(_ root: RootDirectory, regenerateAll: Bool = false,
                                        progress: @escaping (Int, Int) -> Void = { _, _ in }) async throws {
        guard let rootId = root.id else { return }
        let photos = try databaseManager.photosNeedingThumbnails(rootId: rootId, regenerateAll: regenerateAll)
        guard !photos.isEmpty else { return }

        try await SecurityScope.withAccess(root) {
            let total = photos.count
            var completed = 0
            var pending: [(hash: String, path: String)] = []
            var lastFlush = Date()
            let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)

            try await withThrowingTaskGroup(of: (String, String)?.self) { group in
                var iterator = photos.makeIterator()
                func enqueue() {
                    guard let photo = iterator.next() else { return }
                    let source = URL(fileURLWithPath: (root.path as NSString).appendingPathComponent(photo.relativePath))
                    group.addTask(priority: .utility) {
                        let dest = Self.thumbnailURL(forHash: photo.fileHash)
                        if !regenerateAll, FileManager.default.fileExists(atPath: dest.path) {
                            return (photo.fileHash, dest.path)
                        }
                        do {
                            try await Self.createThumbnail(from: source, kind: photo.mediaKind, to: dest)
                            return (photo.fileHash, dest.path)
                        } catch {
                            Self.logger.error("Thumbnail failed for \(photo.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            return nil
                        }
                    }
                }
                for _ in 0..<workers { enqueue() }
                while let result = try await group.next() {
                    try Task.checkCancellation()
                    completed += 1
                    if let result { pending.append(result) }
                    // Write in batches and tell the UI at most every couple of seconds.
                    if pending.count >= 200 || Date().timeIntervalSince(lastFlush) > 2 {
                        try databaseManager.setThumbnails(pending)
                        pending.removeAll(keepingCapacity: true)
                        lastFlush = Date()
                        progress(completed, total)
                        await MainActor.run {
                            NotificationCenter.default.post(name: .thumbnailsUpdated, object: nil)
                        }
                    }
                    enqueue()
                }
            }
            try databaseManager.setThumbnails(pending)
            progress(total, total)
            await MainActor.run {
                NotificationCenter.default.post(name: .thumbnailsUpdated, object: nil)
            }
        }
    }

    static func createThumbnail(from source: URL, kind: MediaKind, to destination: URL) async throws {
        let image: CGImage
        if kind == .video {
            image = try await videoFrame(source)
        } else {
            image = try imageThumbnail(source, maxPixel: thumbnailSize)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = destination.appendingPathExtension("tmp")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ThumbnailError.cannotCreateDestination
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ThumbnailError.cannotSaveThumbnail }
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    /// Uses the preview embedded in the file when it is big enough (RAW files carry a full-size JPEG),
    /// and only decodes the full image otherwise.
    static func imageThumbnail(_ url: URL, maxPixel: CGFloat) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ThumbnailError.cannotCreateImageSource
        }
        let embedded: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, embedded as CFDictionary),
           CGFloat(max(thumb.width, thumb.height)) >= maxPixel * 0.75 {
            return thumb
        }
        var full = embedded
        full.removeValue(forKey: kCGImageSourceCreateThumbnailFromImageIfAbsent)
        full[kCGImageSourceCreateThumbnailFromImageAlways] = true
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, full as CFDictionary) else {
            throw ThumbnailError.cannotCreateThumbnail
        }
        return thumb
    }

    static func videoFrame(_ url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailSize, height: thumbnailSize)
        let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        return image
    }

    /// Removes thumbnails whose content no longer has any catalogue row.
    static func deleteThumbnails(forHashes hashes: [String]) {
        for hash in hashes {
            try? FileManager.default.removeItem(at: thumbnailURL(forHash: hash))
        }
        Task { @MainActor in ThumbnailCache.shared.removeAll() }
    }

    // MARK: - Compatibility

    func getThumbnailURL(for photo: PhotoFile) -> URL? {
        guard photo.hasThumbnail, let path = photo.thumbnailPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Synchronous load; prefer `ThumbnailCache.shared.image(for:)` from views.
    func getThumbnailImage(for photo: PhotoFile) -> NSImage? {
        if let cached = ThumbnailCache.shared.cachedImage(for: photo) { return cached }
        guard let url = getThumbnailURL(for: photo) else { return nil }
        return NSImage(contentsOf: url)
    }
}

extension Notification.Name {
    static let thumbnailsUpdated = Notification.Name("ThumbnailsUpdated")
    static let libraryChanged = Notification.Name("PhotoLibraryChanged")
}

/// Memory-bounded thumbnail cache with off-main-thread loading.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 3000
        c.totalCostLimit = 300 << 20
        return c
    }()

    /// The catalogued thumbnail path, or else where a content-addressed thumbnail for this hash would be
    /// (it may have been generated after this row was loaded).
    private func key(_ photo: PhotoFile) -> NSString? {
        if photo.hasThumbnail, let path = photo.thumbnailPath, !path.isEmpty { return path as NSString }
        guard !photo.fileHash.isEmpty else { return nil }
        return ThumbnailService.thumbnailURL(forHash: photo.fileHash).path as NSString
    }

    func cachedImage(for photo: PhotoFile) -> NSImage? {
        key(photo).flatMap { cache.object(forKey: $0) }
    }

    /// Loads the thumbnail on a background thread. Returns nil when the photo has none yet.
    func image(for photo: PhotoFile) async -> NSImage? {
        guard let key = key(photo) else { return nil }
        if let hit = cache.object(forKey: key) { return hit }
        let path = key as String
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return NSImage(data: data)
        }.value
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    func removeAll() { cache.removeAllObjects() }
}

enum ThumbnailError: Error {
    case rootDirectoryNotFound
    case cannotCreateImageSource
    case cannotCreateThumbnail
    case cannotCreateDestination
    case cannotSaveThumbnail
}
