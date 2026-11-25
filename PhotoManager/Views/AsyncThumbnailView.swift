import SwiftUI
import AppKit

/// Thumbnail loaded off the main thread through `ThumbnailCache`.
struct AsyncThumbnail: View {
    let photo: PhotoFile
    var size: CGFloat = 120
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?
    @EnvironmentObject var photoLibrary: PhotoLibrary

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: photo.mediaKind == .video ? "video" : "photo")
                            .foregroundColor(.gray)
                    )
            }
            if photo.mediaKind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: max(12, size / 6)))
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: "\(photo.id ?? 0)-\(photo.thumbnailPath ?? "")-\(photoLibrary.thumbnailsUpdated.timeIntervalSince1970)") {
            if image == nil || ThumbnailCache.shared.cachedImage(for: photo) == nil {
                // Off the main thread; finds thumbnails generated after this row was loaded.
                image = await ThumbnailCache.shared.image(for: photo)
            }
        }
    }
}

/// Larger previews, generated on demand from the original (using its embedded preview when possible).
enum PreviewLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 60
        return c
    }()

    static func preview(for photo: PhotoFile, library: PhotoLibrary, maxPixel: CGFloat) async -> NSImage? {
        let key = "\(photo.fileHash)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let root = await MainActor.run(body: { library.rootDirectory(id: photo.rootDirectoryId) }) else { return nil }
        let url = URL(fileURLWithPath: (root.path as NSString).appendingPathComponent(photo.relativePath))
        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            await SecurityScope.withAccess(root) { () async -> NSImage? in
                let cg: CGImage?
                if photo.mediaKind == .video {
                    cg = try? await ThumbnailService.videoFrame(url)
                } else {
                    cg = try? ThumbnailService.imageThumbnail(url, maxPixel: maxPixel)
                }
                return cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            }
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

extension PhotoFilter {
    /// Filter for a timeline period key: "2019", "2019-03", "2019-03-12" or "2019-W10" (SQLite %W weeks).
    static func forPeriod(_ key: String) -> PhotoFilter {
        var filter = PhotoFilter()
        if let range = weekRange(key) {
            filter.captureFrom = range.lowerBound
            filter.captureTo = range.upperBound
        } else {
            filter.capturePrefix = key
        }
        return filter
    }

    /// SQLite's %W: week 00 runs from Jan 1 to the day before the first Monday; week n starts n-1 weeks after it.
    static func weekRange(_ key: String) -> Range<Date>? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, parts[1].hasPrefix("W"), let year = Int(parts[0]), let week = Int(parts[1].dropFirst()) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        let weekday = calendar.component(.weekday, from: jan1) // 1 = Sunday, 2 = Monday
        let daysToMonday = (9 - weekday) % 7
        guard let firstMonday = calendar.date(byAdding: .day, value: daysToMonday, to: jan1) else { return nil }
        if week == 0 { return jan1..<firstMonday }
        guard let start = calendar.date(byAdding: .day, value: (week - 1) * 7, to: firstMonday),
              let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        return start..<end
    }
}
