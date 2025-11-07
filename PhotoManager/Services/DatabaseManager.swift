import Foundation
import SQLite
import os.log
//foo
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private static let logger = Logger(subsystem: "com.photomarger", category: "database")
    
    private var db: Connection?
    private let databasePath: String
    
    init() {
        Self.logger.info("Initializing database manager")
        // Create app support directory if it doesn't exist
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("PhotoManager")
        
        Self.logger.info("App directory: \(appDirectory.path, privacy: .public)")
        
        do {
            try FileManager.default.createDirectory(at: appDirectory, 
                                                   withIntermediateDirectories: true)
            Self.logger.info("Created app directory successfully")
        } catch {
            Self.logger.error("Failed to create directory: \(error.localizedDescription, privacy: .public)")
        }
        
        databasePath = appDirectory.appendingPathComponent("PhotoManager.sqlite").path
        Self.logger.info("Database path: \(self.databasePath, privacy: .public)")
        
        do {
            db = try Connection(databasePath)
            Self.logger.info("Database connection successful")
            createTables()
            migrateDatabase()
        } catch {
            Self.logger.error("Database connection failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func createTables() {
        NSLog("📊 DatabaseManager: Creating database tables")
        do {
            // Create root directories table
            NSLog("🗺 DatabaseManager: Creating root directories table")
            try db?.run(DatabaseTables.rootDirectories.create(ifNotExists: true) { table in
                table.column(DatabaseTables.rootDirId, primaryKey: .autoincrement)
                table.column(DatabaseTables.rootDirPath, unique: true)
                table.column(DatabaseTables.rootDirName)
                table.column(DatabaseTables.rootDirIsActive, defaultValue: true)
                table.column(DatabaseTables.rootDirCreatedAt, defaultValue: Date())
                table.column(DatabaseTables.rootDirLastScannedAt)
                table.column(DatabaseTables.rootDirBookmarkData)
            })
            
            // Create photo files table
            try db?.run(DatabaseTables.photoFiles.create(ifNotExists: true) { table in
                table.column(DatabaseTables.photoId, primaryKey: .autoincrement)
                table.column(DatabaseTables.photoRootDirId)
                table.column(DatabaseTables.photoRelativePath)
                table.column(DatabaseTables.photoFileName)
                table.column(DatabaseTables.photoFileExtension)
                table.column(DatabaseTables.photoFileSize)
                table.column(DatabaseTables.photoFileHash)
                table.column(DatabaseTables.photoCreatedAt)
                table.column(DatabaseTables.photoModifiedAt)
                table.column(DatabaseTables.photoExifDateTaken)
                table.column(DatabaseTables.photoExifCameraModel)
                table.column(DatabaseTables.photoExifLensModel)
                table.column(DatabaseTables.photoExifFocalLength)
                table.column(DatabaseTables.photoExifAperture)
                table.column(DatabaseTables.photoExifIso)
                table.column(DatabaseTables.photoExifShutterSpeed)
                table.column(DatabaseTables.photoImageWidth)
                table.column(DatabaseTables.photoImageHeight)
                table.column(DatabaseTables.photoHasThumbnail, defaultValue: false)
                table.column(DatabaseTables.photoThumbnailPath)
                table.column(DatabaseTables.photoUserDescription)
                table.column(DatabaseTables.photoUserTags)
                
                table.foreignKey(DatabaseTables.photoRootDirId,
                               references: DatabaseTables.rootDirectories, 
                               DatabaseTables.rootDirId,
                               delete: .cascade)
            })
            
            // Create indices for performance
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_hash ON photo_files(file_hash)")
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_root_dir ON photo_files(root_directory_id)")
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_date_taken ON photo_files(exif_date_taken)")
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_relative_path ON photo_files(relative_path)")
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_user_description ON photo_files(user_description)")
            try db?.run("CREATE INDEX IF NOT EXISTS idx_photo_user_tags ON photo_files(user_tags)")
            
            NSLog("✅ DatabaseManager: Tables created successfully")
        } catch {
            NSLog("❌ DatabaseManager: Create table error: %@", error.localizedDescription)
        }
    }
    
    private func migrateDatabase() {
        NSLog("📊 DatabaseManager: Checking for database migrations")
        
        guard let db = db else {
            NSLog("❌ DatabaseManager: No database connection for migration")
            return
        }
        
        // Check if new columns exist, if not add them
        do {
            // Try to check if columns exist by querying table info
            let tableInfo = try db.prepare("PRAGMA table_info(photo_files)")
            var columnNames: Set<String> = []
            
            for row in tableInfo {
                if let columnName = row[1] as? String {
                    columnNames.insert(columnName)
                }
            }
            
            // Add user_description column if it doesn't exist
            if !columnNames.contains("user_description") {
                NSLog("🔄 DatabaseManager: Adding user_description column")
                try db.run("ALTER TABLE photo_files ADD COLUMN user_description TEXT")
                NSLog("✅ DatabaseManager: user_description column added")
            }
            
            
            // Add rating column if it doesn't exist
            if !columnNames.contains("rating") {
                NSLog("🔄 DatabaseManager: Adding rating column")
                try db.run("ALTER TABLE photo_files ADD COLUMN rating INTEGER DEFAULT 0")
                NSLog("✅ DatabaseManager: rating column added")
            }
            
            // Add color_tag column if it doesn't exist
            if !columnNames.contains("color_tag") {
                NSLog("🔄 DatabaseManager: Adding color_tag column")
                try db.run("ALTER TABLE photo_files ADD COLUMN color_tag TEXT")
                NSLog("✅ DatabaseManager: color_tag column added")
            }
            
            // Create indices for new columns
            try db.run("CREATE INDEX IF NOT EXISTS idx_photo_user_description ON photo_files(user_description)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_photo_user_tags ON photo_files(user_tags)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_photo_rating ON photo_files(rating)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_photo_color_tag ON photo_files(color_tag)")
            
            NSLog("✅ DatabaseManager: Database migration completed")
        } catch {
            NSLog("❌ DatabaseManager: Migration error: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Root Directory Operations
    
    func addRootDirectory(_ directory: RootDirectory) throws -> Int64 {
        print("🗺 DatabaseManager: Adding root directory - Path: \(directory.path), Name: \(directory.name)")
        guard let db = db else { 
            print("❌ DatabaseManager: No database connection available")
            throw DatabaseError.connectionFailed 
        }
        
        let insert = DatabaseTables.rootDirectories.insert(
            DatabaseTables.rootDirPath <- directory.path,
            DatabaseTables.rootDirName <- directory.name,
            DatabaseTables.rootDirIsActive <- directory.isActive,
            DatabaseTables.rootDirCreatedAt <- directory.createdAt,
            DatabaseTables.rootDirBookmarkData <- directory.bookmarkData
        )
        
        let rowId = try db.run(insert)
        print("✅ DatabaseManager: Successfully added root directory with ID: \(rowId)")
        return rowId
    }
    
    func getRootDirectories() throws -> [RootDirectory] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var directories: [RootDirectory] = []
        
        for row in try db.prepare(DatabaseTables.rootDirectories) {
            directories.append(RootDirectory(
                id: row[DatabaseTables.rootDirId],
                path: row[DatabaseTables.rootDirPath],
                name: row[DatabaseTables.rootDirName],
                isActive: row[DatabaseTables.rootDirIsActive],
                createdAt: row[DatabaseTables.rootDirCreatedAt],
                lastScannedAt: row[DatabaseTables.rootDirLastScannedAt],
                bookmarkData: row[DatabaseTables.rootDirBookmarkData]
            ))
        }
        
        return directories
    }
    
    func updateRootDirectoryLastScanned(_ id: Int64, date: Date) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let directory = DatabaseTables.rootDirectories.filter(DatabaseTables.rootDirId == id)
        try db.run(directory.update(DatabaseTables.rootDirLastScannedAt <- date))
    }
    
    func deleteRootDirectory(_ id: Int64) throws {
        Self.logger.info("Deleting root directory with ID: \(id, privacy: .public)")
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // The foreign key constraint with CASCADE will automatically delete associated photos
        let directory = DatabaseTables.rootDirectories.filter(DatabaseTables.rootDirId == id)
        let deletedRows = try db.run(directory.delete())
        
        if deletedRows > 0 {
            Self.logger.info("Successfully deleted root directory with ID: \(id, privacy: .public)")
        } else {
            Self.logger.warning("No root directory found with ID: \(id, privacy: .public)")
        }
    }
    
    // MARK: - Photo File Operations
    
    func addPhotoFile(_ photo: PhotoFile) throws -> Int64 {
        Self.logger.info("Adding photo file: \(photo.fileName, privacy: .public) to DB")
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let insert = DatabaseTables.photoFiles.insert(
            DatabaseTables.photoRootDirId <- photo.rootDirectoryId,
            DatabaseTables.photoRelativePath <- photo.relativePath,
            DatabaseTables.photoFileName <- photo.fileName,
            DatabaseTables.photoFileExtension <- photo.fileExtension,
            DatabaseTables.photoFileSize <- photo.fileSize,
            DatabaseTables.photoFileHash <- photo.fileHash,
            DatabaseTables.photoCreatedAt <- photo.createdAt,
            DatabaseTables.photoModifiedAt <- photo.modifiedAt,
            DatabaseTables.photoExifDateTaken <- photo.exifDateTaken,
            DatabaseTables.photoExifCameraModel <- photo.exifCameraModel,
            DatabaseTables.photoExifLensModel <- photo.exifLensModel,
            DatabaseTables.photoExifFocalLength <- photo.exifFocalLength,
            DatabaseTables.photoExifAperture <- photo.exifAperture,
            DatabaseTables.photoExifIso <- photo.exifIso,
            DatabaseTables.photoExifShutterSpeed <- photo.exifShutterSpeed,
            DatabaseTables.photoImageWidth <- photo.imageWidth,
            DatabaseTables.photoImageHeight <- photo.imageHeight,
            DatabaseTables.photoHasThumbnail <- photo.hasThumbnail,
            DatabaseTables.photoThumbnailPath <- photo.thumbnailPath,
            DatabaseTables.photoUserDescription <- photo.userDescription,
            DatabaseTables.photoUserTags <- photo.userTags,
            DatabaseTables.photoRating <- photo.rating,
            DatabaseTables.photoColorTag <- photo.colorTag
        )
        
        let photoId = try db.run(insert)
        Self.logger.info("Successfully added photo with ID: \(photoId, privacy: .public)")
        return photoId
    }
    
    func getPhotosForDirectory(_ directoryId: Int64) throws -> [PhotoFile] {
        Self.logger.info("Getting photos for directory ID: \(directoryId, privacy: .public)")
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var photos: [PhotoFile] = []
        let query = DatabaseTables.photoFiles.filter(DatabaseTables.photoRootDirId == directoryId)
        
        for row in try db.prepare(query) {
            photos.append(PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            ))
        }
        
        Self.logger.info("Retrieved \(photos.count, privacy: .public) photos for directory ID: \(directoryId, privacy: .public)")
        return photos
    }
    
    func findDuplicates() throws -> [DuplicateGroup] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var duplicateGroups: [DuplicateGroup] = []
        
        // Find all hashes that appear more than once
        let duplicateHashQuery = """
            SELECT file_hash, COUNT(*) as count, SUM(file_size) as total_size
            FROM photo_files 
            GROUP BY file_hash 
            HAVING COUNT(*) > 1
        """
        
        for row in try db.prepare(duplicateHashQuery) {
            let hash = row[0] as! String
            let totalSize = row[2] as! Int64
            
            // Get all files with this hash
            let filesQuery = DatabaseTables.photoFiles.filter(DatabaseTables.photoFileHash == hash)
            var files: [PhotoFile] = []
            
            for fileRow in try db.prepare(filesQuery) {
                files.append(PhotoFile(
                    id: fileRow[DatabaseTables.photoId],
                    rootDirectoryId: fileRow[DatabaseTables.photoRootDirId],
                    relativePath: fileRow[DatabaseTables.photoRelativePath],
                    fileName: fileRow[DatabaseTables.photoFileName],
                    fileExtension: fileRow[DatabaseTables.photoFileExtension],
                    fileSize: fileRow[DatabaseTables.photoFileSize],
                    fileHash: fileRow[DatabaseTables.photoFileHash],
                    createdAt: fileRow[DatabaseTables.photoCreatedAt],
                    modifiedAt: fileRow[DatabaseTables.photoModifiedAt],
                    exifDateTaken: fileRow[DatabaseTables.photoExifDateTaken],
                    exifCameraModel: fileRow[DatabaseTables.photoExifCameraModel],
                    exifLensModel: fileRow[DatabaseTables.photoExifLensModel],
                    exifFocalLength: fileRow[DatabaseTables.photoExifFocalLength],
                    exifAperture: fileRow[DatabaseTables.photoExifAperture],
                    exifIso: fileRow[DatabaseTables.photoExifIso],
                    exifShutterSpeed: fileRow[DatabaseTables.photoExifShutterSpeed],
                    imageWidth: fileRow[DatabaseTables.photoImageWidth],
                    imageHeight: fileRow[DatabaseTables.photoImageHeight],
                    hasThumbnail: fileRow[DatabaseTables.photoHasThumbnail],
                    thumbnailPath: fileRow[DatabaseTables.photoThumbnailPath],
                    userDescription: fileRow[DatabaseTables.photoUserDescription],
                    userTags: fileRow[DatabaseTables.photoUserTags],
                rating: (try? fileRow.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? fileRow.get(DatabaseTables.photoColorTag)
            ))
            }
            
            duplicateGroups.append(DuplicateGroup(fileHash: hash, files: files, totalSize: totalSize))
        }
        
        return duplicateGroups
    }
    
    func findDuplicatesByDirectory() throws -> [DirectoryDuplicateInfo] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Get root directories map for full paths
        var rootDirMap: [Int64: String] = [:]
        for row in try db.prepare(DatabaseTables.rootDirectories) {
            rootDirMap[row[DatabaseTables.rootDirId]] = row[DatabaseTables.rootDirPath]
        }
        
        // Get all photos and group by directory using full path as key
        var directoryMap: [String: (files: [PhotoFile], rootDirId: Int64, fullPath: String, relativePath: String)] = [:]
        
        for row in try db.prepare(DatabaseTables.photoFiles) {
            let photo = PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            )
            
            // Extract directory path (parent directory)
            let directoryPath = (photo.relativePath as NSString).deletingLastPathComponent
            let rootPath = rootDirMap[photo.rootDirectoryId] ?? ""
            let fullPath = (rootPath as NSString).appendingPathComponent(directoryPath)
            
            // Use full path as key to distinguish directories with same relative path in different roots
            if var existing = directoryMap[fullPath] {
                existing.files.append(photo)
                directoryMap[fullPath] = existing
            } else {
                directoryMap[fullPath] = (files: [photo], rootDirId: photo.rootDirectoryId, fullPath: fullPath, relativePath: directoryPath)
            }
        }
        
        // Get duplicate hashes
        let duplicateHashQuery = """
            SELECT file_hash FROM photo_files 
            GROUP BY file_hash 
            HAVING COUNT(*) > 1
        """
        var duplicateHashes = Set<String>()
        for row in try db.prepare(duplicateHashQuery) {
            duplicateHashes.insert(row[0] as! String)
        }
        
        // Build directory duplicate info
        var directoryDuplicateInfos: [DirectoryDuplicateInfo] = []
        
        for (fullPath, dirData) in directoryMap {
            let files = dirData.files
            let duplicateFiles = files.filter { duplicateHashes.contains($0.fileHash) }
            
            if !duplicateFiles.isEmpty {
                let wastedSize = duplicateFiles.reduce(Int64(0)) { sum, file in
                    // Count how many copies exist minus one
                    let copyCount = files.filter { $0.fileHash == file.fileHash }.count
                    return sum + (copyCount > 1 ? file.fileSize * Int64(copyCount - 1) : 0)
                }
                
                let totalSize = files.reduce(Int64(0)) { $0 + $1.fileSize }
                
                directoryDuplicateInfos.append(DirectoryDuplicateInfo(
                    directoryPath: dirData.relativePath,
                    fullPath: dirData.fullPath,
                    fileCount: files.count,
                    duplicateFileCount: duplicateFiles.count,
                    totalSize: totalSize,
                    wastedSize: wastedSize,
                    files: duplicateFiles,
                    rootDirectoryId: dirData.rootDirId
                ))
            }
        }
        
        return directoryDuplicateInfos.sorted { $0.duplicateFileCount > $1.duplicateFileCount }
    }
    
    func findCompleteDuplicateDirectories() throws -> [CompleteDuplicateDirectory] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Get root directories map for full paths
        var rootDirMap: [Int64: String] = [:]
        for row in try db.prepare(DatabaseTables.rootDirectories) {
            rootDirMap[row[DatabaseTables.rootDirId]] = row[DatabaseTables.rootDirPath]
        }
        
        // Group photos by directory using full path as key to distinguish directories with same relative path
        var directoryMap: [String: (files: [PhotoFile], rootDirId: Int64, fullPath: String, relativePath: String)] = [:]
        
        for row in try db.prepare(DatabaseTables.photoFiles) {
            let photo = PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            )
            
            let directoryPath = (photo.relativePath as NSString).deletingLastPathComponent
            let rootPath = rootDirMap[photo.rootDirectoryId] ?? ""
            let fullPath = (rootPath as NSString).appendingPathComponent(directoryPath)
            
            // Use full path as key to distinguish directories with same relative path in different roots
            if var existing = directoryMap[fullPath] {
                existing.files.append(photo)
                directoryMap[fullPath] = existing
            } else {
                directoryMap[fullPath] = (files: [photo], rootDirId: photo.rootDirectoryId, fullPath: fullPath, relativePath: directoryPath)
            }
        }
        
        // Find directories with identical file sets (by hash)
        var hashSetMap: [Set<String>: [(fullPath: String, data: (files: [PhotoFile], rootDirId: Int64, fullPath: String, relativePath: String))]] = [:]
        
        for (fullPath, dirData) in directoryMap {
            let hashSet = Set(dirData.files.map { $0.fileHash })
            hashSetMap[hashSet, default: []].append((fullPath: fullPath, data: dirData))
        }
        
        // Build complete duplicate directory groups
        var completeDuplicates: [CompleteDuplicateDirectory] = []
        
        for (_, directories) in hashSetMap where directories.count > 1 {
            let sortedDirectories = directories.sorted { $0.fullPath < $1.fullPath }
            let primaryDir = sortedDirectories.first!
            let duplicateDirs = Array(sortedDirectories.dropFirst())
            
            let totalSize = primaryDir.data.files.reduce(Int64(0)) { $0 + $1.fileSize }
            
            let primaryDirInfo = DirectoryInfo(
                relativePath: primaryDir.data.relativePath,
                fullPath: primaryDir.data.fullPath,
                files: primaryDir.data.files,
                rootDirectoryId: primaryDir.data.rootDirId
            )
            
            let duplicateDirInfos = duplicateDirs.map { dir in
                DirectoryInfo(
                    relativePath: dir.data.relativePath,
                    fullPath: dir.data.fullPath,
                    files: dir.data.files,
                    rootDirectoryId: dir.data.rootDirId
                )
            }
            
            completeDuplicates.append(CompleteDuplicateDirectory(
                primaryDirectory: primaryDirInfo,
                duplicateDirectories: duplicateDirInfos,
                fileCount: primaryDir.data.files.count,
                totalSize: totalSize
            ))
        }
        
        return completeDuplicates.sorted { $0.fileCount > $1.fileCount }
    }
    
    func deletePhotosInDirectory(_ directoryPath: String) throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Find all photos in this directory
        var photoIds: [Int64] = []
        
        for row in try db.prepare(DatabaseTables.photoFiles) {
            let relativePath = row[DatabaseTables.photoRelativePath]
            let photoDirectoryPath = (relativePath as NSString).deletingLastPathComponent
            
            if photoDirectoryPath == directoryPath {
                photoIds.append(row[DatabaseTables.photoId])
            }
        }
        
        // Delete all photos in this directory
        for photoId in photoIds {
            let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
            try db.run(photo.delete())
        }
        
        return photoIds.count
    }
    
    func moveDirectoryToTrash(_ fullDirectoryPath: String) throws {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: fullDirectoryPath)
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: fullDirectoryPath, isDirectory: &isDirectory)
        
        if !exists {
            NSLog("⚠️ DatabaseManager: Directory does not exist (may have been deleted): \(fullDirectoryPath)")
            throw DatabaseError.queryFailed("Directory does not exist: \(fullDirectoryPath)")
        }
        
        if !isDirectory.boolValue {
            NSLog("⚠️ DatabaseManager: Path exists but is not a directory: \(fullDirectoryPath)")
            throw DatabaseError.queryFailed("Path is not a directory: \(fullDirectoryPath)")
        }
        
        NSLog("🗑️ DatabaseManager: Moving directory to trash: \(fullDirectoryPath)")
        
        // Move to trash using FileManager
        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: directoryURL, resultingItemURL: &resultingURL)
            
            if let trashedURL = resultingURL {
                NSLog("✅ DatabaseManager: Successfully moved to trash at: \(trashedURL.path ?? "unknown")")
            } else {
                NSLog("✅ DatabaseManager: Successfully moved to trash")
            }
        } catch {
            NSLog("❌ DatabaseManager: Failed to move to trash: \(error.localizedDescription)")
            throw error
        }
    }
    
    func deletePhoto(_ photoId: Int64) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        try db.run(photo.delete())
    }
    
    func clearPhotosForDirectory(_ directoryId: Int64) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let photos = DatabaseTables.photoFiles.filter(DatabaseTables.photoRootDirId == directoryId)
        try db.run(photos.delete())
    }
    
    func updateThumbnailPath(_ photoId: Int64, thumbnailPath: String) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        try db.run(photo.update(
            DatabaseTables.photoHasThumbnail <- true,
            DatabaseTables.photoThumbnailPath <- thumbnailPath
        ))
    }
    
    func getPhotoById(_ photoId: Int64) throws -> PhotoFile? {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        
        if let row = try db.pluck(query) {
            return PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            )
        }
        
        return nil
    }
    
    func updatePhotoMetadata(_ photoId: Int64, description: String?, tags: String?) throws {
        NSLog("📝 DatabaseManager: updatePhotoMetadata called for ID: %lld", photoId)
        NSLog("   Description: %@", description ?? "nil")
        NSLog("   Tags: %@", tags ?? "nil")
        
        guard let db = db else { 
            NSLog("❌ DatabaseManager: No database connection")
            throw DatabaseError.connectionFailed 
        }
        
        let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        let rowsAffected = try db.run(photo.update(
            DatabaseTables.photoUserDescription <- description,
            DatabaseTables.photoUserTags <- tags
        ))
        
        NSLog("✅ DatabaseManager: Updated %d row(s)", rowsAffected)
        
        // Verify the update
        if let updatedRow = try db.pluck(photo) {
            let savedDesc = updatedRow[DatabaseTables.photoUserDescription]
            let savedTags = updatedRow[DatabaseTables.photoUserTags]
            NSLog("✓ Verification - Description: %@", savedDesc ?? "nil")
            NSLog("✓ Verification - Tags: %@", savedTags ?? "nil")
        }
    }
    
    func updatePhotoRating(_ photoId: Int64, rating: Int) throws {
        NSLog("⭐ DatabaseManager: updatePhotoRating called for ID: %lld, rating: %d", photoId, rating)
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Validate rating is in range 0-5
        let validRating = min(max(rating, 0), 5)
        
        let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        try db.run(photo.update(DatabaseTables.photoRating <- validRating))
        NSLog("✅ DatabaseManager: Updated rating to %d", validRating)
    }
    
    func updatePhotoColorTag(_ photoId: Int64, colorTag: String?) throws {
        NSLog("🎨 DatabaseManager: updatePhotoColorTag called for ID: %lld, color: %@", photoId, colorTag ?? "nil")
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let photo = DatabaseTables.photoFiles.filter(DatabaseTables.photoId == photoId)
        try db.run(photo.update(DatabaseTables.photoColorTag <- colorTag))
        NSLog("✅ DatabaseManager: Updated color tag")
    }
    
    func searchPhotos(query: String, minRating: Int? = nil, colorTag: String? = nil) throws -> [PhotoFile] {
        NSLog("🔍 DatabaseManager: Searching - query: %@, minRating: %@, colorTag: %@", 
              query, String(describing: minRating), colorTag ?? "nil")
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var photos: [PhotoFile] = []
        let searchPattern = "%\(query)%"
        
        // Build search query with optional rating and color filters
        var searchQuery = DatabaseTables.photoFiles
        
        // Text search
        if !query.isEmpty {
            searchQuery = searchQuery.filter(
                DatabaseTables.photoFileName.like(searchPattern) ||
                DatabaseTables.photoRelativePath.like(searchPattern) ||
                DatabaseTables.photoUserDescription.like(searchPattern) ||
                DatabaseTables.photoUserTags.like(searchPattern)
            )
        }
        
        // Rating filter
        if let minRating = minRating {
            searchQuery = searchQuery.filter(DatabaseTables.photoRating >= minRating)
        }
        
        // Color tag filter
        if let colorTag = colorTag {
            searchQuery = searchQuery.filter(DatabaseTables.photoColorTag == colorTag)
        }
        
        for row in try db.prepare(searchQuery) {
            photos.append(PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            ))
        }
        
        return photos
    }
    
    func getPhotosByRating(minRating: Int) throws -> [PhotoFile] {
        NSLog("⭐ DatabaseManager: Getting photos with rating >= %d", minRating)
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var photos: [PhotoFile] = []
        let query = DatabaseTables.photoFiles.filter(DatabaseTables.photoRating >= minRating)
        
        for row in try db.prepare(query) {
            photos.append(PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            ))
        }
        
        NSLog("✅ DatabaseManager: Found %d photos with rating >= %d", photos.count, minRating)
        return photos
    }
    
    func getPhotosByColorTag(_ colorTag: String) throws -> [PhotoFile] {
        NSLog("🎨 DatabaseManager: Getting photos with color tag: %@", colorTag)
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var photos: [PhotoFile] = []
        let query = DatabaseTables.photoFiles.filter(DatabaseTables.photoColorTag == colorTag)
        
        for row in try db.prepare(query) {
            photos.append(PhotoFile(
                id: row[DatabaseTables.photoId],
                rootDirectoryId: row[DatabaseTables.photoRootDirId],
                relativePath: row[DatabaseTables.photoRelativePath],
                fileName: row[DatabaseTables.photoFileName],
                fileExtension: row[DatabaseTables.photoFileExtension],
                fileSize: row[DatabaseTables.photoFileSize],
                fileHash: row[DatabaseTables.photoFileHash],
                createdAt: row[DatabaseTables.photoCreatedAt],
                modifiedAt: row[DatabaseTables.photoModifiedAt],
                exifDateTaken: row[DatabaseTables.photoExifDateTaken],
                exifCameraModel: row[DatabaseTables.photoExifCameraModel],
                exifLensModel: row[DatabaseTables.photoExifLensModel],
                exifFocalLength: row[DatabaseTables.photoExifFocalLength],
                exifAperture: row[DatabaseTables.photoExifAperture],
                exifIso: row[DatabaseTables.photoExifIso],
                exifShutterSpeed: row[DatabaseTables.photoExifShutterSpeed],
                imageWidth: row[DatabaseTables.photoImageWidth],
                imageHeight: row[DatabaseTables.photoImageHeight],
                hasThumbnail: row[DatabaseTables.photoHasThumbnail],
                thumbnailPath: row[DatabaseTables.photoThumbnailPath],
                userDescription: row[DatabaseTables.photoUserDescription],
                userTags: row[DatabaseTables.photoUserTags],
                rating: (try? row.get(DatabaseTables.photoRating)) ?? 0,
                colorTag: try? row.get(DatabaseTables.photoColorTag)
            ))
        }
        
        NSLog("✅ DatabaseManager: Found %d photos with color tag: %@", photos.count, colorTag)
        return photos
    }
    
    // MARK: - Debug Operations
    
    func executeRawSQL(_ sql: String) async throws -> ([String], [[String: String]]) {
        return try await Task.detached {
            guard let db = self.db else { throw DatabaseError.connectionFailed }
            
            var columnNames: [String] = []
            var results: [[String: String]] = []
            
            // Execute the query
            let statement = try db.prepare(sql)
            
            // Get column names from the statement
            columnNames = statement.columnNames
            
            // Fetch all rows
            for row in statement {
                var rowDict: [String: String] = [:]
                
                for (index, columnName) in columnNames.enumerated() {
                    // Convert the value to string representation
                    let value: String
                    if let stringValue = row[index] as? String {
                        value = stringValue
                    } else if let intValue = row[index] as? Int64 {
                        value = String(intValue)
                    } else if let doubleValue = row[index] as? Double {
                        value = String(doubleValue)
                    } else if let boolValue = row[index] as? Bool {
                        value = String(boolValue)
                    } else if let dateValue = row[index] as? Date {
                        let formatter = ISO8601DateFormatter()
                        value = formatter.string(from: dateValue)
                    } else if let dataValue = row[index] as? Data {
                        value = "<Data: \(dataValue.count) bytes>"
                    } else if row[index] == nil {
                        value = "NULL"
                    } else {
                        value = String(describing: row[index]!)
                    }
                    
                    rowDict[columnName] = value
                }
                
                results.append(rowDict)
            }
            
            return (columnNames, results)
        }.value
    }
}

enum DatabaseError: Error {
    case connectionFailed
    case queryFailed(String)
}
