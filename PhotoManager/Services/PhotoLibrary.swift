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
    
    func scanDirectory(_ directory: RootDirectory) async {
        logger.info("Starting scanDirectory for: \(directory.name, privacy: .public) at \(directory.path, privacy: .public)")
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            logger.info("Calling fileScanningService.scanDirectory")
            // Scan for files and extract metadata
            try await fileScanningService.scanDirectory(directory)
            logger.info("File scanning completed successfully")
            
            // Generate thumbnails
            if let directoryId = directory.id {
                print("🖼 PhotoLibrary: Generating thumbnails for directory ID: \(directoryId)")
                try await thumbnailService.generateThumbnailsForDirectory(directoryId)
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
    
    func getPhotoById(_ photoId: Int64) -> PhotoFile? {
        do {
            return try databaseManager.getPhotoById(photoId)
        } catch {
            print("❌ PhotoLibrary: Failed to get photo by ID: \(error.localizedDescription)")
            return nil
        }
    }
    
    func searchPhotos(query: String) -> [PhotoFile] {
        guard !query.isEmpty else { return [] }
        
        do {
            return try databaseManager.searchPhotos(query: query)
        } catch {
            errorMessage = "Failed to search photos: \(error.localizedDescription)"
            return []
        }
    }
}
