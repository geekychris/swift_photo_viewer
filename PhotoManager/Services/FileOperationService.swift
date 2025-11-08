import Foundation
import AppKit

class FileOperationService {
    private let photoLibrary: PhotoLibrary
    private let databaseManager: DatabaseManager
    
    init(photoLibrary: PhotoLibrary, databaseManager: DatabaseManager) {
        self.photoLibrary = photoLibrary
        self.databaseManager = databaseManager
    }
    
    // MARK: - Copy Operations
    
    func copyPhotos(_ photos: [PhotoFile], to destination: Destination, completionHandler: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var copiedCount = 0
            var lastError: Error?
            
            for photo in photos {
                if let result = self.copyPhoto(photo, to: destination), result {
                    copiedCount += 1
                } else {
                    lastError = NSError(domain: "FileOperationService", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to copy \(photo.fileName)"
                    ])
                }
            }
            
            DispatchQueue.main.async {
                if let error = lastError, copiedCount == 0 {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(copiedCount))
                }
            }
        }
    }
    
    private func copyPhoto(_ photo: PhotoFile, to destination: Destination) -> Bool? {
        guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            return false
        }
        
        let sourcePath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return false
        }
        
        let destPath: String
        let destRootDirectoryId: Int64?
        
        switch destination {
        case .managedDirectory(let directory):
            destPath = (directory.path as NSString).appendingPathComponent(photo.fileName)
            destRootDirectoryId = directory.id
            
        case .unmanagedPath(let path):
            destPath = (path as NSString).appendingPathComponent(photo.fileName)
            destRootDirectoryId = nil
        }
        
        let destURL = URL(fileURLWithPath: destPath)
        
        do {
            // Handle security-scoped resources
            var sourceAccessGranted = false
            if let bookmarkData = rootDirectory.bookmarkData {
                if let directoryURL = try? URL(resolvingBookmarkData: bookmarkData,
                                              options: [.withSecurityScope],
                                              relativeTo: nil,
                                              bookmarkDataIsStale: nil) {
                    sourceAccessGranted = directoryURL.startAccessingSecurityScopedResource()
                }
            }
            
            defer {
                if sourceAccessGranted, let bookmarkData = rootDirectory.bookmarkData {
                    if let directoryURL = try? URL(resolvingBookmarkData: bookmarkData,
                                                  options: [.withSecurityScope],
                                                  relativeTo: nil,
                                                  bookmarkDataIsStale: nil) {
                        directoryURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
            
            // Copy the file
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            
            // If destination is a managed directory, add to database
            if let destRootId = destRootDirectoryId {
                try databaseManager.db.write { db in
                    try db.execute(sql: """
                        INSERT INTO photo_files (
                            root_directory_id, relative_path, file_name, file_size,
                            image_width, image_height, has_thumbnail,
                            exif_date_taken, exif_camera_model, exif_lens_model,
                            exif_aperture, exif_shutter_speed, exif_iso, exif_focal_length,
                            user_description, user_tags, rating, color_tag, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        destRootId,
                        photo.fileName,
                        photo.fileName,
                        photo.fileSize,
                        photo.imageWidth,
                        photo.imageHeight,
                        false, // Will regenerate thumbnail
                        photo.exifDateTaken,
                        photo.exifCameraModel,
                        photo.exifLensModel,
                        photo.exifAperture,
                        photo.exifShutterSpeed,
                        photo.exifIso,
                        photo.exifFocalLength,
                        photo.userDescription,
                        photo.userTags,
                        photo.rating,
                        photo.colorTag,
                        Date()
                    ])
                }
                
                // Trigger rescan to generate thumbnail
                DispatchQueue.main.async {
                    self.photoLibrary.loadDirectories()
                }
            }
            
            return true
        } catch {
            print("Error copying file: \(error)")
            return false
        }
    }
    
    // MARK: - Move Operations
    
    func movePhotos(_ photos: [PhotoFile], to destination: Destination, completionHandler: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var movedCount = 0
            var lastError: Error?
            
            for photo in photos {
                if let result = self.movePhoto(photo, to: destination), result {
                    movedCount += 1
                } else {
                    lastError = NSError(domain: "FileOperationService", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to move \(photo.fileName)"
                    ])
                }
            }
            
            DispatchQueue.main.async {
                if let error = lastError, movedCount == 0 {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(movedCount))
                }
            }
        }
    }
    
    private func movePhoto(_ photo: PhotoFile, to destination: Destination) -> Bool? {
        guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            return false
        }
        
        let sourcePath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return false
        }
        
        let destPath: String
        let destRootDirectoryId: Int64?
        
        switch destination {
        case .managedDirectory(let directory):
            destPath = (directory.path as NSString).appendingPathComponent(photo.fileName)
            destRootDirectoryId = directory.id
            
        case .unmanagedPath(let path):
            destPath = (path as NSString).appendingPathComponent(photo.fileName)
            destRootDirectoryId = nil
        }
        
        let destURL = URL(fileURLWithPath: destPath)
        
        do {
            // Handle security-scoped resources
            var sourceAccessGranted = false
            if let bookmarkData = rootDirectory.bookmarkData {
                if let directoryURL = try? URL(resolvingBookmarkData: bookmarkData,
                                              options: [.withSecurityScope],
                                              relativeTo: nil,
                                              bookmarkDataIsStale: nil) {
                    sourceAccessGranted = directoryURL.startAccessingSecurityScopedResource()
                }
            }
            
            defer {
                if sourceAccessGranted, let bookmarkData = rootDirectory.bookmarkData {
                    if let directoryURL = try? URL(resolvingBookmarkData: bookmarkData,
                                                  options: [.withSecurityScope],
                                                  relativeTo: nil,
                                                  bookmarkDataIsStale: nil) {
                        directoryURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
            
            // Move the file
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            
            // Update database
            if let photoId = photo.id {
                if let destRootId = destRootDirectoryId {
                    // Moving to another managed directory
                    try databaseManager.db.write { db in
                        try db.execute(sql: """
                            UPDATE photo_files
                            SET root_directory_id = ?,
                                relative_path = ?,
                                updated_at = ?
                            WHERE id = ?
                        """, arguments: [destRootId, photo.fileName, Date(), photoId])
                    }
                } else {
                    // Moving to unmanaged location - remove from database
                    try databaseManager.db.write { db in
                        try db.execute(sql: "DELETE FROM photo_files WHERE id = ?", arguments: [photoId])
                    }
                }
                
                // Reload directories
                DispatchQueue.main.async {
                    self.photoLibrary.loadDirectories()
                }
            }
            
            return true
        } catch {
            print("Error moving file: \(error)")
            return false
        }
    }
}

// MARK: - Destination Type

enum Destination {
    case managedDirectory(PhotoDirectory)
    case unmanagedPath(String)
}
