import Foundation
import SwiftUI
import os.log
//foo
private let logger = Logger(subsystem: "com.photomarger", category: "photolibrary")

class PhotoLibrary: ObservableObject {
    private let databaseManager = DatabaseManager.shared
    private let fileScanningService = FileScanningService()
    private let thumbnailService = ThumbnailService()
    
    @Published var rootDirectories: [RootDirectory] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var directoryDuplicates: [DirectoryDuplicateInfo] = []
    @Published var completeDuplicateDirectories: [CompleteDuplicateDirectory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var thumbnailsUpdated = Date() // Triggers UI refresh when thumbnails are generated
    
    init() {
        print("📚 PhotoLibrary: Initializing photo library")
        loadRootDirectories()
        loadDuplicates()
        print("✅ PhotoLibrary: Photo library initialization complete")
        
        // Set up notification listener for thumbnail updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ThumbnailsUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thumbnailsUpdated = Date()
        }
    }
    
    func loadRootDirectories() {
        print("📚 PhotoLibrary: Loading root directories from database")
        do {
            rootDirectories = try databaseManager.getRootDirectories()
            print("✅ PhotoLibrary: Successfully loaded \(rootDirectories.count) root directories")
            for (index, dir) in rootDirectories.enumerated() {
                print("➡️ PhotoLibrary: Directory \(index + 1): \(dir.name) (ID: \(dir.id ?? -1)) - \(dir.path)")
            }
        } catch {
            let errorMsg = "Failed to load directories: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
        }
    }
    
    func addRootDirectory(path: String, name: String, bookmarkData: Data?) {
        NSLog("🗺 PhotoLibrary: Adding directory - Path: %@, Name: %@", path, name)
        if bookmarkData != nil {
            NSLog("✅ PhotoLibrary: Bookmark data provided for directory")
        } else {
            NSLog("⚠️ PhotoLibrary: No bookmark data for directory")
        }
        do {
            let directory = RootDirectory(path: path, name: name, bookmarkData: bookmarkData)
            let newDirectoryId = try databaseManager.addRootDirectory(directory)
            NSLog("✅ PhotoLibrary: Successfully added directory with ID: %ld", newDirectoryId)
            loadRootDirectories()
            
            // Find the newly added directory and scan it automatically
            if let newDirectory = rootDirectories.first(where: { $0.id == newDirectoryId }) {
            NSLog("🔍 PhotoLibrary: Starting automatic scan for directory: %@", newDirectory.name)
                Task {
                    await scanDirectory(newDirectory)
                }
            } else {
                print("❌ PhotoLibrary: Could not find newly added directory with ID: \(newDirectoryId)")
            }
        } catch {
            let errorMsg = "Failed to add directory: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
        }
    }
    
    func scanDirectory(_ directory: RootDirectory, fastScan: Bool = false, regenerateThumbnails: Bool = false) async {
        logger.info("Starting scanDirectory for: \(directory.name, privacy: .public) at \(directory.path, privacy: .public)")
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            logger.info("Calling fileScanningService.scanDirectory (fastScan: \(fastScan, privacy: .public))")
            // Scan for files and extract metadata
            try await fileScanningService.scanDirectory(directory, fastScan: fastScan)
            logger.info("File scanning completed successfully")
            
            // Generate thumbnails
            if let directoryId = directory.id {
                print("🖼 PhotoLibrary: Generating thumbnails for directory ID: \(directoryId) (regenerateAll: \(regenerateThumbnails))")
                try await thumbnailService.generateThumbnailsForDirectory(directoryId, regenerateAll: regenerateThumbnails)
                print("✅ PhotoLibrary: Thumbnail generation completed")
            } else {
                print("❌ PhotoLibrary: No directory ID available for thumbnail generation")
            }
            
            await MainActor.run {
                print("🔄 PhotoLibrary: Reloading directories and duplicates")
                loadRootDirectories()
                loadDuplicates()
                isLoading = false
                // Force UI refresh
                objectWillChange.send()
                print("✅ PhotoLibrary: Scan completed successfully")
            }
            
        } catch {
            let errorMsg = "Failed to scan directory: \(error.localizedDescription)"
            logger.error("Failed to scan directory: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                errorMessage = errorMsg
                isLoading = false
            }
        }
    }
    
    func getPhotosForDirectory(_ directoryId: Int64) -> [PhotoFile] {
        print("📷 PhotoLibrary: Getting photos for directory ID: \(directoryId)")
        do {
            let photos = try databaseManager.getPhotosForDirectory(directoryId)
            print("✅ PhotoLibrary: Found \(photos.count) photos for directory ID: \(directoryId)")
            return photos
        } catch {
            let errorMsg = "Failed to load photos: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
            return []
        }
    }
    
    func loadDuplicates() {
        do {
            duplicateGroups = try databaseManager.findDuplicates()
            directoryDuplicates = try databaseManager.findDuplicatesByDirectory()
            completeDuplicateDirectories = try databaseManager.findCompleteDuplicateDirectories()
        } catch {
            errorMessage = "Failed to load duplicates: \(error.localizedDescription)"
        }
    }
    
    func getThumbnailImage(for photo: PhotoFile) -> NSImage? {
        return thumbnailService.getThumbnailImage(for: photo)
    }
    
    func deletePhoto(_ photoId: Int64) {
        do {
            try databaseManager.deletePhoto(photoId)
            loadDuplicates() // Refresh duplicates after deletion
        } catch {
            errorMessage = "Failed to delete photo: \(error.localizedDescription)"
        }
    }
    
    func movePhotoToTrash(_ photo: PhotoFile) {
        print("🗑️ PhotoLibrary: Moving photo to trash: \(photo.fileName)")
        print("   Root directory ID: \(photo.rootDirectoryId)")
        print("   Relative path: \(photo.relativePath)")
        
        // Find the root directory to get bookmark data
        guard let rootDir = rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            let error = "Root directory not found for ID: \(photo.rootDirectoryId)"
            print("❌ PhotoLibrary: \(error)")
            errorMessage = error
            return
        }
        
        // Start accessing security-scoped resource if bookmark data exists
        var securityScopedURL: URL?
        if let bookmarkData = rootDir.bookmarkData {
            do {
                var isStale = false
                securityScopedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    print("⚠️ PhotoLibrary: Bookmark data is stale for directory: \(rootDir.name)")
                }
                
                if let url = securityScopedURL {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    print("🔓 PhotoLibrary: Started security-scoped access: \(didStartAccessing)")
                }
            } catch {
                print("⚠️ PhotoLibrary: Failed to resolve bookmark: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ PhotoLibrary: No bookmark data for root directory: \(rootDir.name)")
        }
        
        // Ensure we stop accessing the resource when done
        defer {
            if let url = securityScopedURL {
                url.stopAccessingSecurityScopedResource()
                print("🔒 PhotoLibrary: Stopped security-scoped access")
            }
        }
        
        do {
            // Get the absolute full file path using extension
            guard let fullPath = photo.getAbsoluteFullPath(rootDirectories: rootDirectories) else {
                let error = "Could not construct absolute path for file: \(photo.fileName)"
                print("❌ PhotoLibrary: \(error)")
                throw DatabaseError.queryFailed(error)
            }
            
            let fileURL = URL(fileURLWithPath: fullPath)
            
            print("   Absolute path: \(fullPath)")
            print("   File URL: \(fileURL.path)")
            
            // Check if file exists
            if FileManager.default.fileExists(atPath: fullPath) {
                print("   File exists, attempting to move to trash...")
                // Move to trash
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)
                if let trashedPath = resultingURL?.path {
                    print("✅ PhotoLibrary: Moved file to trash at: \(trashedPath)")
                } else {
                    print("✅ PhotoLibrary: Moved file to trash")
                }
            } else {
                print("⚠️ PhotoLibrary: File doesn't exist at path: \(fullPath)")
                print("   Will still remove from database")
            }
            
            // Delete thumbnail
            try? thumbnailService.deleteThumbnail(for: photo)
            print("✅ PhotoLibrary: Deleted thumbnail")
            
            // Remove from database
            if let photoId = photo.id {
                try databaseManager.deletePhoto(photoId)
                print("✅ PhotoLibrary: Removed from database (ID: \(photoId))")
            }
            
            // Note: Don't refresh duplicates here - caller should batch refresh
            // after multiple deletions to avoid rescanning database for each file
            objectWillChange.send()
            
        } catch {
            let fullError = "Failed to move photo to trash: \(error.localizedDescription)"
            errorMessage = fullError
            print("❌ PhotoLibrary: \(fullError)")
            print("   File: \(photo.fileName)")
            print("   Relative path: \(photo.relativePath)")
            print("   Root directory ID: \(photo.rootDirectoryId)")
        }
    }
    
    func deleteAllDuplicatesInDirectory(_ dirInfo: DirectoryDuplicateInfo) {
        print("🗑️ PhotoLibrary: Deleting all \(dirInfo.duplicateFileCount) duplicates in: \(dirInfo.fullPath)")
        
        var successCount = 0
        var failureCount = 0
        
        for file in dirInfo.files {
            do {
                // Get absolute full path using extension
                guard let fullPath = file.getAbsoluteFullPath(rootDirectories: rootDirectories) else {
                    print("⚠️ Could not construct absolute path for: \(file.fileName)")
                    failureCount += 1
                    continue
                }
                
                let fileURL = URL(fileURLWithPath: fullPath)
                
                // Move to trash if exists
                if FileManager.default.fileExists(atPath: fullPath) {
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                } else {
                    print("⚠️ File doesn't exist: \(file.fileName) at \(fullPath)")
                }
                
                // Delete thumbnail
                try? thumbnailService.deleteThumbnail(for: file)
                
                // Remove from database
                if let photoId = file.id {
                    try databaseManager.deletePhoto(photoId)
                    successCount += 1
                }
            } catch {
                print("❌ Failed to delete \(file.fileName): \(error.localizedDescription)")
                failureCount += 1
            }
        }
        
        print("✅ PhotoLibrary: Deleted \(successCount) files, \(failureCount) failures")
        
        // Refresh duplicates
        loadDuplicates()
        objectWillChange.send()
    }
    
    func deleteRootDirectory(_ directory: RootDirectory) {
        logger.info("Deleting root directory: \(directory.name, privacy: .public)")
        guard let directoryId = directory.id else {
            logger.error("Cannot delete directory without ID")
            errorMessage = "Cannot delete directory: No ID found"
            return
        }
        
        do {
            // Get all photos for this directory to clean up thumbnails
            let photos = try databaseManager.getPhotosForDirectory(directoryId)
            
            // Delete thumbnails
            for photo in photos {
                try? thumbnailService.deleteThumbnail(for: photo)
            }
            
            // Delete directory from database (cascades to photos)
            try databaseManager.deleteRootDirectory(directoryId)
            logger.info("Successfully deleted root directory")
            
            // Reload data
            loadRootDirectories()
            loadDuplicates()
            
            // Force UI refresh
            objectWillChange.send()
        } catch {
            let errorMsg = "Failed to delete directory: \(error.localizedDescription)"
            logger.error("Failed to delete directory: \(error.localizedDescription, privacy: .public)")
            errorMessage = errorMsg
        }
    }
    
    func getPhotosGroupedByDate() -> [(String, [PhotoFile])] {
        var allPhotos: [PhotoFile] = []
        
        // Collect all photos from all directories
        for directory in rootDirectories {
            if let directoryId = directory.id {
                allPhotos.append(contentsOf: getPhotosForDirectory(directoryId))
            }
        }
        
        // Group by year-month
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        
        let grouped = Dictionary(grouping: allPhotos) { photo in
            if let dateTaken = photo.exifDateTaken {
                return dateFormatter.string(from: dateTaken)
            } else {
                return dateFormatter.string(from: photo.createdAt)
            }
        }
        
        return grouped.sorted { $0.key > $1.key } // Most recent first
    }
    
    func getPhotosGroupedByYear() -> [(String, [(String, [PhotoFile])])] {
        let monthlyGroups = getPhotosGroupedByDate()
        
        let yearlyGroups = Dictionary(grouping: monthlyGroups) { group in
            String(group.0.prefix(4)) // Extract year from YYYY-MM
        }
        
        return yearlyGroups.map { year, months in
            (year, months.sorted { $0.0 > $1.0 })
        }.sorted { $0.0 > $1.0 }
    }
    
    func getPhotosGroupedByYearAndWeek() -> [(String, [(String, [PhotoFile])])] {
        var allPhotos: [PhotoFile] = []
        
        // Collect all photos from all directories
        for directory in rootDirectories {
            if let directoryId = directory.id {
                allPhotos.append(contentsOf: getPhotosForDirectory(directoryId))
            }
        }
        
        // Group by year and week
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allPhotos) { photo -> String in
            let date = photo.exifDateTaken ?? photo.createdAt
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let week = calendar.component(.weekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        }
        
        let sortedGroups = grouped.sorted { $0.key > $1.key }
        
        // Group by year
        let yearlyGroups = Dictionary(grouping: sortedGroups) { group in
            String(group.key.prefix(4)) // Extract year from YYYY-Www
        }
        
        return yearlyGroups.map { year, weeks in
            (year, weeks.sorted { $0.0 > $1.0 })
        }.sorted { $0.0 > $1.0 }
    }
    
    func getPhotosGroupedByYearAndDay() -> [(String, [(String, [PhotoFile])])] {
        var allPhotos: [PhotoFile] = []
        
        // Collect all photos from all directories
        for directory in rootDirectories {
            if let directoryId = directory.id {
                allPhotos.append(contentsOf: getPhotosForDirectory(directoryId))
            }
        }
        
        // Group by day
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let grouped = Dictionary(grouping: allPhotos) { photo in
            let date = photo.exifDateTaken ?? photo.createdAt
            return dateFormatter.string(from: date)
        }
        
        let sortedGroups = grouped.sorted { $0.key > $1.key }
        
        // Group by year
        let yearlyGroups = Dictionary(grouping: sortedGroups) { group in
            String(group.key.prefix(4)) // Extract year from YYYY-MM-DD
        }
        
        return yearlyGroups.map { year, days in
            (year, days.sorted { $0.0 > $1.0 })
        }.sorted { $0.0 > $1.0 }
    }
    
    func updatePhotoMetadata(_ photoId: Int64, description: String?, tags: String?) {
        print("📚 PhotoLibrary: updatePhotoMetadata called for ID: \(photoId)")
        do {
            try databaseManager.updatePhotoMetadata(photoId, description: description, tags: tags)
            print("✅ PhotoLibrary: Successfully updated metadata")
            // Force immediate UI refresh
            objectWillChange.send()
        } catch {
            let errorMsg = "Failed to update photo metadata: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
        }
    }
    
    func updatePhotoRating(_ photoId: Int64, rating: Int) {
        print("⭐ PhotoLibrary: updatePhotoRating called for ID: \(photoId), rating: \(rating)")
        do {
            try databaseManager.updatePhotoRating(photoId, rating: rating)
            print("✅ PhotoLibrary: Successfully updated rating")
            objectWillChange.send()
        } catch {
            let errorMsg = "Failed to update photo rating: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
        }
    }
    
    func updatePhotoColorTag(_ photoId: Int64, colorTag: String?) {
        print("🎨 PhotoLibrary: updatePhotoColorTag called for ID: \(photoId), color: \(colorTag ?? "none")")
        do {
            try databaseManager.updatePhotoColorTag(photoId, colorTag: colorTag)
            print("✅ PhotoLibrary: Successfully updated color tag")
            objectWillChange.send()
        } catch {
            let errorMsg = "Failed to update photo color tag: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMsg)")
            errorMessage = errorMsg
        }
    }
    
    func getPhotoById(_ photoId: Int64) -> PhotoFile? {
        do {
            return try databaseManager.getPhotoById(photoId)
        } catch {
            print("❌ PhotoLibrary: Failed to get photo by ID: \(error.localizedDescription)")
            return nil
        }
    }
    
    func searchPhotos(query: String, minRating: Int? = nil, colorTag: String? = nil) -> [PhotoFile] {
        do {
            return try databaseManager.searchPhotos(query: query, minRating: minRating, colorTag: colorTag)
        } catch {
            errorMessage = "Failed to search photos: \(error.localizedDescription)"
            return []
        }
    }
    
    func getPhotosByRating(minRating: Int) -> [PhotoFile] {
        do {
            return try databaseManager.getPhotosByRating(minRating: minRating)
        } catch {
            errorMessage = "Failed to get photos by rating: \(error.localizedDescription)"
            return []
        }
    }
    
    func getPhotosByColorTag(_ colorTag: String) -> [PhotoFile] {
        do {
            return try databaseManager.getPhotosByColorTag(colorTag)
        } catch {
            errorMessage = "Failed to get photos by color tag: \(error.localizedDescription)"
            return []
        }
    }
    
    func exportDuplicatesToCSV(includeDirectoryView: Bool = false) -> URL? {
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "duplicates_export_\(timestamp).csv"
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            var csvContent = ""
            
            if includeDirectoryView {
                // Export directory-based duplicates (already uses fullPath which is absolute)
                csvContent += "Directory Path,Total Files,Duplicate Files,Duplicate %,Total Size,Wasted Size\n"
                
                for dirInfo in directoryDuplicates {
                    let totalSizeStr = ByteCountFormatter().string(fromByteCount: dirInfo.totalSize)
                    let wastedSizeStr = ByteCountFormatter().string(fromByteCount: dirInfo.wastedSize)
                    let duplicatePercent = String(format: "%.1f", dirInfo.duplicatePercentage)
                    // Use fullPath (absolute) instead of directoryPath (which might be relative)
                    csvContent += "\"\(dirInfo.fullPath)\",\(dirInfo.fileCount),\(dirInfo.duplicateFileCount),\(duplicatePercent)%,\(totalSizeStr),\(wastedSizeStr)\n"
                }
                
                csvContent += "\n\nComplete Duplicate Directories\n"
                csvContent += "Primary Directory,Duplicate Directories,File Count,Total Size\n"
                
                for completeDir in completeDuplicateDirectories {
                    let totalSizeStr = ByteCountFormatter().string(fromByteCount: completeDir.totalSize)
                    let dupDirs = completeDir.duplicateDirectories.map { $0.fullPath }.joined(separator: "; ")
                    
                    csvContent += "\"\(completeDir.primaryDirectory.fullPath)\",\"\(dupDirs)\",\(completeDir.fileCount),\(totalSizeStr)\n"
                }
            } else {
                // Export file-based duplicates
                csvContent += "File Hash,Duplicate Count,Total Size,File Name,Locations\n"
                
                for group in duplicateGroups {
                    // Filter files to only those with valid absolute paths
                    let filesWithValidPaths = group.files.compactMap { file -> (file: PhotoFile, path: String)? in
                        guard let absolutePath = file.getAbsoluteFullPath(rootDirectories: rootDirectories) else {
                            return nil
                        }
                        return (file, absolutePath)
                    }
                    
                    // Skip groups with no valid paths
                    guard !filesWithValidPaths.isEmpty else { continue }
                    
                    let actualDuplicateCount = filesWithValidPaths.count
                    let totalSize = filesWithValidPaths.reduce(0) { $0 + $1.file.fileSize }
                    let totalSizeStr = ByteCountFormatter().string(fromByteCount: totalSize)
                    let fileName = filesWithValidPaths.first?.file.fileName ?? ""
                    let locations = filesWithValidPaths.map { $0.path }.joined(separator: "; ")
                    
                    csvContent += "\"\(group.fileHash)\",\(actualDuplicateCount),\(totalSizeStr),\"\(fileName)\",\"\(locations)\"\n"
                }
            }
            
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ PhotoLibrary: Exported duplicates to \(fileURL.path)")
            return fileURL
        } catch {
            errorMessage = "Failed to export CSV: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMessage!)")
            return nil
        }
    }
    
    func deleteDuplicateDirectory(_ directoryPath: String) {
        do {
            let deletedCount = try databaseManager.deletePhotosInDirectory(directoryPath)
            print("✅ PhotoLibrary: Deleted \(deletedCount) photos from directory: \(directoryPath)")
            loadDuplicates()
            objectWillChange.send()
        } catch {
            errorMessage = "Failed to delete directory: \(error.localizedDescription)"
            print("❌ PhotoLibrary: \(errorMessage!)")
        }
    }
    
    func moveDirectoryToTrash(_ directoryInfo: DirectoryInfo) {
        print("🗑️ PhotoLibrary: Starting deletion process for: \(directoryInfo.fullPath)")
        print("   Directory contains \(directoryInfo.files.count) files")
        
        var filesMovedToTrash = false
        
        // Try to move files to trash
        do {
            try databaseManager.moveDirectoryToTrash(directoryInfo.fullPath)
            print("✅ PhotoLibrary: Moved directory to trash: \(directoryInfo.fullPath)")
            filesMovedToTrash = true
        } catch {
            // Directory might not exist on disk anymore
            print("⚠️ PhotoLibrary: Could not move to trash: \(error.localizedDescription)")
            print("   Will still remove from database")
        }
        
        // Remove specific photos from database by their IDs
        var deletedCount = 0
        var failedCount = 0
        
        print("💾 PhotoLibrary: Removing \(directoryInfo.files.count) files from database...")
        
        for (index, file) in directoryInfo.files.enumerated() {
            if let photoId = file.id {
                do {
                    try databaseManager.deletePhoto(photoId)
                    deletedCount += 1
                } catch {
                    failedCount += 1
                    print("⚠️ PhotoLibrary: Failed to delete photo ID \(photoId) (\(file.fileName)): \(error.localizedDescription)")
                }
            } else {
                print("⚠️ PhotoLibrary: File has no ID, skipping: \(file.fileName)")
                failedCount += 1
            }
            
            // Progress indicator for large directories
            if (index + 1) % 100 == 0 {
                print("   Progress: \(index + 1)/\(directoryInfo.files.count) files processed")
            }
        }
        
        print("✅ PhotoLibrary: Removed \(deletedCount) photos from database")
        if failedCount > 0 {
            print("⚠️ PhotoLibrary: Failed to remove \(failedCount) photos")
        }
        
        // Reload duplicates to reflect changes
        print("🔄 PhotoLibrary: Reloading duplicate analysis...")
        loadDuplicates()
        
        // Force UI refresh
        objectWillChange.send()
        
        print("✅ PhotoLibrary: Database refreshed after deletion")
        print("📊 PhotoLibrary: Current state - \(duplicateGroups.count) duplicate groups, \(completeDuplicateDirectories.count) complete duplicate directories")
    }
}
