import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
//foo
class ThumbnailService: ObservableObject {
    private let databaseManager = DatabaseManager.shared
    private let thumbnailSize: CGFloat = 300
    private let thumbnailDirectory: URL
    
    @Published var isGeneratingThumbnails = false
    @Published var thumbnailProgress: Double = 0.0
    
    init() {
        // Create thumbnails directory in app support
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("PhotoManager")
        thumbnailDirectory = appDirectory.appendingPathComponent("Thumbnails")
        
        try? FileManager.default.createDirectory(at: thumbnailDirectory, 
                                               withIntermediateDirectories: true)
    }
    
    func generateThumbnailsForDirectory(_ directoryId: Int64) async throws {
        await MainActor.run {
            isGeneratingThumbnails = true
            thumbnailProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                isGeneratingThumbnails = false
                thumbnailProgress = 0.0
            }
        }
        
        let photos = try databaseManager.getPhotosForDirectory(directoryId)
        let photosWithoutThumbnails = photos.filter { !$0.hasThumbnail }
        
        for (index, photo) in photosWithoutThumbnails.enumerated() {
            await MainActor.run {
                thumbnailProgress = Double(index) / Double(photosWithoutThumbnails.count)
            }
            
            do {
                try await generateThumbnail(for: photo)
            } catch {
                print("Error generating thumbnail for \(photo.fileName): \(error)")
            }
        }
    }
    
    func generateThumbnail(for photo: PhotoFile) async throws {
        guard let photoId = photo.id else { return }
        
        // Get root directory to construct full path
        let rootDirectories = try databaseManager.getRootDirectories()
        guard let rootDirectory = rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            throw ThumbnailError.rootDirectoryNotFound
        }
        
        let fullImagePath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
        let imageURL = URL(fileURLWithPath: fullImagePath)
        
        // Generate unique thumbnail filename
        let thumbnailFileName = "\(photoId)_\(photo.fileHash.prefix(8)).jpg"
        let thumbnailURL = thumbnailDirectory.appendingPathComponent(thumbnailFileName)
        
        // Generate thumbnail
        try await createThumbnail(from: imageURL, to: thumbnailURL, size: thumbnailSize)
        
        // Update database with thumbnail path
        try databaseManager.updateThumbnailPath(photoId, thumbnailPath: thumbnailURL.path)
    }
    
    private func createThumbnail(from sourceURL: URL, to destinationURL: URL, size: CGFloat) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                        throw ThumbnailError.cannotCreateImageSource
                    }
                    
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: size
                    ]
                    
                    guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        throw ThumbnailError.cannotCreateThumbnail
                    }
                    
                    // Save thumbnail as JPEG
                    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, 
                                                                          UTType.jpeg.identifier as CFString, 1, nil) else {
                        throw ThumbnailError.cannotCreateDestination
                    }
                    
                    let compressionOptions: [CFString: Any] = [
                        kCGImageDestinationLossyCompressionQuality: 0.8
                    ]
                    
                    CGImageDestinationAddImage(destination, thumbnailImage, compressionOptions as CFDictionary)
                    
                    if CGImageDestinationFinalize(destination) {
                        continuation.resume()
                    } else {
                        throw ThumbnailError.cannotSaveThumbnail
                    }
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func getThumbnailURL(for photo: PhotoFile) -> URL? {
        guard let thumbnailPath = photo.thumbnailPath, photo.hasThumbnail else {
            return nil
        }
        return URL(fileURLWithPath: thumbnailPath)
    }
    
    func getThumbnailImage(for photo: PhotoFile) -> NSImage? {
        guard let thumbnailURL = getThumbnailURL(for: photo) else {
            return nil
        }
        return NSImage(contentsOf: thumbnailURL)
    }
    
    func deleteThumbnail(for photo: PhotoFile) throws {
        guard let thumbnailURL = getThumbnailURL(for: photo) else { return }
        
        try FileManager.default.removeItem(at: thumbnailURL)
        
        if let photoId = photo.id {
            // Update database to reflect thumbnail removal
            try databaseManager.updateThumbnailPath(photoId, thumbnailPath: "")
        }
    }
    
    func cleanupOrphanedThumbnails() async throws {
        let fileManager = FileManager.default
        let thumbnailFiles = try fileManager.contentsOfDirectory(at: thumbnailDirectory, 
                                                               includingPropertiesForKeys: nil)
        
        // Get all photos with thumbnails
        let rootDirectories = try databaseManager.getRootDirectories()
        var allPhotos: [PhotoFile] = []
        
        for directory in rootDirectories {
            if let directoryId = directory.id {
                let photos = try databaseManager.getPhotosForDirectory(directoryId)
                allPhotos.append(contentsOf: photos)
            }
        }
        
        let validThumbnailPaths = Set(allPhotos.compactMap { $0.thumbnailPath })
        
        // Delete orphaned thumbnails
        for thumbnailFile in thumbnailFiles {
            if !validThumbnailPaths.contains(thumbnailFile.path) {
                try fileManager.removeItem(at: thumbnailFile)
            }
        }
    }
}

enum ThumbnailError: Error {
    case rootDirectoryNotFound
    case cannotCreateImageSource
    case cannotCreateThumbnail
    case cannotCreateDestination
    case cannotSaveThumbnail
}
