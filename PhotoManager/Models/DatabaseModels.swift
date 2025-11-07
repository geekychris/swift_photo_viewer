import Foundation
import SQLite

// MARK: - Database Models
//foo
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
    
    var fullPath: String {
        return relativePath
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fileHash)
    }
    
    static func == (lhs: PhotoFile, rhs: PhotoFile) -> Bool {
        return lhs.fileHash == rhs.fileHash
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
    
    // Photo Files columns
    static let photoId = Expression<Int64>("id")
    static let photoRootDirId = Expression<Int64>("root_directory_id")
    static let photoRelativePath = Expression<String>("relative_path")
    static let photoFileName = Expression<String>("file_name")
    static let photoFileExtension = Expression<String>("file_extension")
    static let photoFileSize = Expression<Int64>("file_size")
    static let photoFileHash = Expression<String>("file_hash")
    static let photoCreatedAt = Expression<Date>("created_at")
    static let photoModifiedAt = Expression<Date>("modified_at")
    static let photoExifDateTaken = Expression<Date?>("exif_date_taken")
    static let photoExifCameraModel = Expression<String?>("exif_camera_model")
    static let photoExifLensModel = Expression<String?>("exif_lens_model")
    static let photoExifFocalLength = Expression<Double?>("exif_focal_length")
    static let photoExifAperture = Expression<Double?>("exif_aperture")
    static let photoExifIso = Expression<Int?>("exif_iso")
    static let photoExifShutterSpeed = Expression<String?>("exif_shutter_speed")
    static let photoImageWidth = Expression<Int?>("image_width")
    static let photoImageHeight = Expression<Int?>("image_height")
    static let photoHasThumbnail = Expression<Bool>("has_thumbnail")
    static let photoThumbnailPath = Expression<String?>("thumbnail_path")
    static let photoUserDescription = Expression<String?>("user_description")
    static let photoUserTags = Expression<String?>("user_tags")
    static let photoRating = Expression<Int>("rating")
    static let photoColorTag = Expression<String?>("color_tag")
}
