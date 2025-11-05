import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import os.log
import CoreImage
import Metal

class ThumbnailService: ObservableObject {
    private static let logger = Logger(subsystem: "com.photomarger", category: "thumbnails")
    private let databaseManager = DatabaseManager.shared
    private let thumbnailSize: CGFloat = 300
    private let thumbnailDirectory: URL
    private let ciContext: CIContext?
    private let useMetalAcceleration: Bool
    
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
        
        // Initialize Metal/Core Image acceleration if available
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            // Check if device supports Apple Silicon (Apple GPU family)
            #if arch(arm64)
            useMetalAcceleration = true
            ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
            Self.logger.info("Metal acceleration enabled for thumbnail generation on Apple Silicon")
            #else
            useMetalAcceleration = false
            ciContext = nil
            Self.logger.info("Running on Intel, using standard thumbnail generation")
            #endif
        } else {
            useMetalAcceleration = false
            ciContext = nil
            Self.logger.info("Metal not available, using standard thumbnail generation")
        }
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
        
        // Group photos by root directory to batch security-scoped access
        let photosByRoot = Dictionary(grouping: photosWithoutThumbnails) { $0.rootDirectoryId }
        
        var processedCount = 0
        let totalCount = photosWithoutThumbnails.count
        
        for (rootId, photosForRoot) in photosByRoot {
            // Get root directory once per batch
            let rootDirectories = try databaseManager.getRootDirectories()
            guard let rootDirectory = rootDirectories.first(where: { $0.id == rootId }) else {
                Self.logger.error("Root directory not found for ID \(rootId)")
                continue
            }
            
            // Start security-scoped access once for this batch
            var directoryURL: URL? = nil
            var isAccessingSecurityScope = false
            
            if let bookmarkData = rootDirectory.bookmarkData {
                Self.logger.debug("Restoring security-scoped access for thumbnail generation (batch of \(photosForRoot.count) photos)")
                do {
                    var isStale = false
                    directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                          options: [.withSecurityScope],
                                          relativeTo: nil,
                                          bookmarkDataIsStale: &isStale)
                    
                    if let url = directoryURL {
                        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                        if !isAccessingSecurityScope {
                            Self.logger.error("Failed to start accessing security-scoped resource for thumbnails")
                        }
                    }
                } catch {
                    Self.logger.error("Failed to resolve bookmark for thumbnails: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            // Process all photos in this batch while security scope is active
            for (batchIndex, photo) in photosForRoot.enumerated() {
                await MainActor.run {
                    thumbnailProgress = Double(processedCount) / Double(totalCount)
                }
                
                do {
                    try await generateThumbnailWithoutScopeAccess(for: photo, rootDirectory: rootDirectory)
                } catch {
                    Self.logger.error("Error generating thumbnail for \(photo.fileName): \(error.localizedDescription, privacy: .public)")
                }
                
                processedCount += 1
                
                // Notify UI every 100 photos to trigger refresh for large directories
                if batchIndex % 100 == 0 {
                    await MainActor.run {
                        objectWillChange.send()
                        NotificationCenter.default.post(name: NSNotification.Name("ThumbnailsUpdated"), object: nil)
                    }
                }
            }
            
            // Stop security-scoped access after processing this batch
            if isAccessingSecurityScope, let url = directoryURL {
                url.stopAccessingSecurityScopedResource()
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
        
        // Restore security-scoped access from bookmark
        var directoryURL: URL? = nil
        var isAccessingSecurityScope = false
        
        if let bookmarkData = rootDirectory.bookmarkData {
            Self.logger.debug("Restoring security-scoped access for thumbnail generation")
            do {
                var isStale = false
                directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: [.withSecurityScope],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)
                
                if let url = directoryURL {
                    isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                    if !isAccessingSecurityScope {
                        Self.logger.error("Failed to start accessing security-scoped resource for thumbnails")
                    }
                }
            } catch {
                Self.logger.error("Failed to resolve bookmark for thumbnails: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        defer {
            if isAccessingSecurityScope, let url = directoryURL {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        try await generateThumbnailWithoutScopeAccess(for: photo, rootDirectory: rootDirectory)
    }
    
    private func generateThumbnailWithoutScopeAccess(for photo: PhotoFile, rootDirectory: RootDirectory) async throws {
        guard let photoId = photo.id else { return }
        
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
        if useMetalAcceleration, let ciContext = ciContext {
            try await createThumbnailWithMetal(from: sourceURL, to: destinationURL, size: size, context: ciContext)
        } else {
            try await createThumbnailLegacy(from: sourceURL, to: destinationURL, size: size)
        }
    }
    
    private func createThumbnailWithMetal(from sourceURL: URL, to destinationURL: URL, size: CGFloat, context: CIContext) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Use ImageIO to load image incrementally and get metadata
                    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                        throw ThumbnailError.cannotCreateImageSource
                    }
                    
                    // Load image with downsampling options to avoid memory issues
                    // kCGImageSourceCreateThumbnailWithTransform automatically applies EXIF orientation
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: size * 2  // Load at 2x for better quality input
                    ]
                    
                    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        throw ThumbnailError.cannotCreateThumbnail
                    }
                    
                    // Convert to CIImage - orientation already applied by ImageIO
                    let ciImage = CIImage(cgImage: downsampledImage)
                    
                    let imageSize = ciImage.extent.size
                    let scale = min(size / imageSize.width, size / imageSize.height)
                    
                    // Only scale if we need to reduce size further
                    var outputImage = ciImage
                    if scale < 1.0 {
                        let filter = CIFilter(name: "CILanczosScaleTransform")!
                        filter.setValue(ciImage, forKey: kCIInputImageKey)
                        filter.setValue(scale, forKey: kCIInputScaleKey)
                        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
                        
                        guard let scaledImage = filter.outputImage else {
                            throw ThumbnailError.cannotCreateThumbnail
                        }
                        outputImage = scaledImage
                    }
                    
                    // Create CGImage from CIImage using Metal-accelerated context
                    guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
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
                    
                    CGImageDestinationAddImage(destination, cgImage, compressionOptions as CFDictionary)
                    
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
    
    private func createThumbnailLegacy(from sourceURL: URL, to destinationURL: URL, size: CGFloat) async throws {
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
