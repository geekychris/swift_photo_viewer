import Foundation
import SQLite

// MARK: - Database Models

struct RootDirectory: Identifiable, Equatable {
    let id: Int64?
    let path: String
    let name: String
    let isActive: Bool
    let createdAt: Date
    let lastScannedAt: Date?
    let bookmarkData: Data?

    init(id: Int64? = nil, path: String, name: String, isActive: Bool = true, createdAt: Date = Date(), lastScannedAt: Date? = nil, bookmarkData: Data? = nil) {
        self.id = id
        self.path = path
        self.name = name
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastScannedAt = lastScannedAt
        self.bookmarkData = bookmarkData
    }
}

/// What kind of file a catalogue row is. RAW files are filed in a RAW/ subfolder next to their JPEGs.
enum MediaKind: String, CaseIterable {
    case image
    case raw
    case video

    static let rawExtensions: Set<String> = ["raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "raf", "pef", "srw", "x3f", "3fr", "iiq", "erf", "kdc", "mrw", "rwl"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "gif", "bmp", "webp"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts", "3gp"]
    static let allExtensions = rawExtensions.union(imageExtensions).union(videoExtensions)

    init?(fileExtension: String) {
        let ext = fileExtension.lowercased()
        if Self.rawExtensions.contains(ext) { self = .raw }
        else if Self.imageExtensions.contains(ext) { self = .image }
        else if Self.videoExtensions.contains(ext) { self = .video }
        else { return nil }
    }
}

/// Where a photo's capture date came from, most to least trustworthy.
enum DateSource: String {
    case exif       // EXIF DateTimeOriginal
    case video      // QuickTime creation date
    case filename   // e.g. IMG_20190312_101502.jpg
    case file       // file modification date: unreliable after copying from cards
}

struct PhotoFile: Identifiable, Hashable {
    let id: Int64?
    let rootDirectoryId: Int64
    let relativePath: String
    let fileName: String
    let fileExtension: String
    let fileSize: Int64
    let fileHash: String
    let createdAt: Date
    let modifiedAt: Date
    let exifDateTaken: Date?
    let exifCameraModel: String?
    let exifLensModel: String?
    let exifFocalLength: Double?
    let exifAperture: Double?
    let exifIso: Int?
    let exifShutterSpeed: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let hasThumbnail: Bool
    let thumbnailPath: String?
    var userDescription: String?
    var userTags: String?
    var rating: Int // 0-5 stars/flags
    var colorTag: String? // Color tag: red, orange, yellow, green, blue, purple, gray

    // Added in schema v2
    /// Best known capture time: EXIF wall-clock time read in the current time zone (EXIF has no zone),
    /// so it displays as shot; video dates keep their local wall-clock time the same way.
    var captureDate: Date = Date(timeIntervalSince1970: 0)
    var dateSource: DateSource = .file
    var mediaKind: MediaKind = .image
    var gpsLatitude: Double? = nil
    var gpsLongitude: Double? = nil
    var contentIdentifier: String? = nil
    var eventId: Int64? = nil

    var fullPath: String {
        return relativePath
    }

    /// Directory part of relativePath ("" for files directly in the root)
    var directoryPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// File name without extension, lowercased; used to pair RAW+JPEG and Live Photo stills with their videos.
    var baseName: String {
        ((fileName as NSString).deletingPathExtension).lowercased()
    }

    // Identity is the catalogue row, not the content: two copies of the same photo are different files.
    func hash(into hasher: inout Hasher) {
        if let id { hasher.combine(id) } else {
            hasher.combine(rootDirectoryId)
            hasher.combine(relativePath)
        }
    }

    static func == (lhs: PhotoFile, rhs: PhotoFile) -> Bool {
        if let l = lhs.id, let r = rhs.id { return l == r }
        return lhs.rootDirectoryId == rhs.rootDirectoryId && lhs.relativePath == rhs.relativePath
    }
}

struct DuplicateGroup {
    let fileHash: String
    let files: [PhotoFile]
    let totalSize: Int64

    var duplicateCount: Int {
        return files.count
    }
}

struct DirectoryDuplicateInfo {
    let directoryPath: String
    let fullPath: String
    let fileCount: Int
    let duplicateFileCount: Int
    let totalSize: Int64
    /// Bytes freed by removing this directory's duplicated files (each has a copy elsewhere)
    let wastedSize: Int64
    let files: [PhotoFile]
    let rootDirectoryId: Int64

    var duplicatePercentage: Double {
        guard fileCount > 0 else { return 0 }
        return Double(duplicateFileCount) / Double(fileCount) * 100
    }
}

struct DirectoryInfo: Identifiable, Hashable {
    var id: String { fullPath }
    let relativePath: String
    let fullPath: String
    let files: [PhotoFile]
    let rootDirectoryId: Int64

    func hash(into hasher: inout Hasher) {
        hasher.combine(fullPath)
    }

    static func == (lhs: DirectoryInfo, rhs: DirectoryInfo) -> Bool {
        return lhs.fullPath == rhs.fullPath
    }
}

struct CompleteDuplicateDirectory {
    let primaryDirectory: DirectoryInfo
    let duplicateDirectories: [DirectoryInfo]
    let fileCount: Int
    let totalSize: Int64

    var allDirectories: [DirectoryInfo] {
        return [primaryDirectory] + duplicateDirectories
    }

    var isCompleteDuplicate: Bool {
        return fileCount > 0
    }
}

// MARK: - Events, tags and organise plans (schema v2)

/// A node in the user's event hierarchy, e.g. "Asia Trip" > "Hong Kong" > "Temples".
/// Events are the logical organisation; the physical folder tree is generated from them.
struct PhotoEvent: Identifiable, Hashable {
    let id: Int64
    var parentId: Int64?
    var name: String
    var kind: String          // trip, event, place, subject: informational only
    var place: String?
    var notes: String?
    // Derived from member photos (including descendants) when loaded
    var photoCount: Int = 0
    var startDate: Date?
    var endDate: Date?
}

enum TagKind: String, CaseIterable {
    case person
    case keyword
}

struct PhotoTag: Identifiable, Hashable {
    let id: Int64
    let name: String
    let kind: TagKind
    var photoCount: Int = 0
}

/// Filter shared by the grid, the analytics views and the organise workbench.
/// Every field narrows the result; nil means "any".
struct PhotoFilter: Equatable {
    var rootDirectoryId: Int64?
    var directoryPath: String?            // relative to the root
    var includeSubdirectories = false
    var captureFrom: Date?                // floating wall-clock, inclusive
    var captureTo: Date?                  // exclusive
    var capturePrefix: String?            // "2019", "2019-03", "2019-03-12" on capture_local
    var eventId: Int64?
    var includeSubEvents = true
    var unassignedOnly = false            // no event yet
    var text: String?
    var minRating: Int?
    var colorTags: Set<String> = []
    var tagIds: Set<Int64> = []           // photo must have all of these
    var mediaKinds: Set<MediaKind> = []
    var cameraModel: String?
    var lensModel: String?
    var hasGPS: Bool?
    var duplicatesOnly = false
    var dateSources: Set<DateSource> = []
    var photoIds: [Int64]?                // explicit set (e.g. a cluster)
    /// Drill-down from analytics: the photo's value for each dimension must equal the key.
    var dimensionKeys: [DimensionKey] = []
    var geoBox: GeoBox?
    
    static let all = PhotoFilter()
}

struct DimensionKey: Equatable, Hashable, Codable {
    let dimension: PivotDimension
    let key: String
}

struct GeoBox: Equatable, Hashable, Codable {
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
}

enum PhotoSort: String, CaseIterable {
    case captureAscending
    case captureDescending
    case path
    case name
    case sizeDescending
}

// MARK: - Database Tables

class DatabaseTables {
    static let rootDirectories = Table("root_directories")
    static let photoFiles = Table("photo_files")

    // Root Directories columns
    static let rootDirId = Expression<Int64>("id")
    static let rootDirPath = Expression<String>("path")
    static let rootDirName = Expression<String>("name")
    static let rootDirIsActive = Expression<Bool>("is_active")
    static let rootDirCreatedAt = Expression<Date>("created_at")
    static let rootDirLastScannedAt = Expression<Date?>("last_scanned_at")
    static let rootDirBookmarkData = Expression<Data?>("bookmark_data")
}
