import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import os.log
//foo
class FileScanningService: ObservableObject {
    private let databaseManager = DatabaseManager.shared
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "raw", "cr2", "nef", "arw", "dng", "orf", "rw2"]
    private static let logger = Logger(subsystem: "com.photomarger", category: "scanning")
    
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentFile: String = ""
    
    func scanDirectory(_ rootDirectory: RootDirectory, fastScan: Bool = false) async throws {
        Self.logger.info("Starting scan of directory: \(rootDirectory.path, privacy: .public) (Fast scan: \(fastScan, privacy: .public))")
        
        // Restore security-scoped access from bookmark
        var directoryURL: URL? = nil
        var isAccessingSecurityScope = false
        
        if let bookmarkData = rootDirectory.bookmarkData {
            Self.logger.info("Restoring security-scoped access from bookmark")
            do {
                var isStale = false
                directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: [.withSecurityScope],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)
                
                if isStale {
                    Self.logger.warning("Bookmark data is stale")
                }
                
                if let url = directoryURL {
                    isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                    if isAccessingSecurityScope {
                        Self.logger.info("Successfully restored security-scoped access")
                    } else {
                        Self.logger.error("Failed to start accessing security-scoped resource")
                    }
                }
            } catch {
                Self.logger.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            Self.logger.warning("No bookmark data available for directory")
        }
        
        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
        }
        
        defer {
            if isAccessingSecurityScope, let url = directoryURL {
                url.stopAccessingSecurityScopedResource()
                Self.logger.info("Stopped accessing security-scoped resource")
            }
            Task { @MainActor in
                isScanning = false
                scanProgress = 0.0
                currentFile = ""
            }
        }
        
        // Get existing photos for fast scan comparison
        var existingPhotos: [String: PhotoFile] = [:]
        if fastScan, let directoryId = rootDirectory.id {
            Self.logger.info("Fast scan mode: Loading existing photos for directory ID: \(directoryId, privacy: .public)")
            let photos = try databaseManager.getPhotosForDirectory(directoryId)
            existingPhotos = Dictionary(uniqueKeysWithValues: photos.map { ($0.relativePath, $0) })
            Self.logger.info("Loaded \(existingPhotos.count, privacy: .public) existing photos for comparison")
        } else if !fastScan, let directoryId = rootDirectory.id {
            // Full scan: Clear existing photos for this directory
            Self.logger.info("Full scan mode: Clearing existing photos for directory ID: \(directoryId, privacy: .public)")
            try databaseManager.clearPhotosForDirectory(directoryId)
        } else {
            Self.logger.warning("No directory ID available")
        }
        
        // Get all image files in the directory
        Self.logger.info("Searching for image files in: \(rootDirectory.path, privacy: .public)")
        let imageFiles = try await findImageFiles(in: rootDirectory.path)
        let totalFiles = imageFiles.count
        Self.logger.info("Found \(totalFiles, privacy: .public) image files")
        
        for (index, filePath) in imageFiles.enumerated() {
            await MainActor.run {
                currentFile = URL(fileURLWithPath: filePath).lastPathComponent
                scanProgress = Double(index) / Double(totalFiles)
            }
            
            Self.logger.info("Processing file \(index + 1, privacy: .public)/\(totalFiles, privacy: .public): \(URL(fileURLWithPath: filePath).lastPathComponent, privacy: .public)")
            do {
                try await processImageFile(filePath, rootDirectory: rootDirectory, existingPhotos: existingPhotos, fastScan: fastScan)
                Self.logger.info("Successfully processed: \(URL(fileURLWithPath: filePath).lastPathComponent, privacy: .public)")
            } catch {
                Self.logger.error("Error processing file \(filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // Update last scanned time
        if let directoryId = rootDirectory.id {
            Self.logger.info("Updating last scanned time for directory ID: \(directoryId, privacy: .public)")
            try databaseManager.updateRootDirectoryLastScanned(directoryId, date: Date())
        }
        Self.logger.info("Completed scanning directory: \(rootDirectory.path, privacy: .public)")
    }
    
    private func findImageFiles(in directoryPath: String) async throws -> [String] {
        var imageFiles: [String] = []
        
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directoryPath)
        
        Self.logger.info("Creating enumerator for directory: \(directoryPath, privacy: .public)")
        
        guard let enumerator = fileManager.enumerator(at: directoryURL,
                                                      includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                      options: [.skipsHiddenFiles]) else {
            Self.logger.error("Failed to create directory enumerator for: \(directoryPath, privacy: .public)")
            throw FileScanningError.fileNotFound
        }
        
        var fileCount = 0
        for case let fileURL as URL in enumerator {
            fileCount += 1
            if fileCount == 1 {
                Self.logger.info("First file from enumerator: \(fileURL.lastPathComponent, privacy: .public)")
            }
            let fileExtension = fileURL.pathExtension.lowercased()
            
            if supportedImageExtensions.contains(fileExtension) {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == false {
                        imageFiles.append(fileURL.path)
                        if imageFiles.count % 100 == 0 {
                            Self.logger.info("Found \(imageFiles.count, privacy: .public) images so far...")
                        }
                    }
                } catch {
                    Self.logger.warning("Could not check if \(fileURL.lastPathComponent, privacy: .public) is directory: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        Self.logger.info("Enumerator returned \(fileCount, privacy: .public) total files/folders")
        
        Self.logger.info("Total image files found: \(imageFiles.count, privacy: .public)")
        return imageFiles
    }
    
    private func processImageFile(_ filePath: String, rootDirectory: RootDirectory, existingPhotos: [String: PhotoFile], fastScan: Bool) async throws {
        guard let rootDirectoryId = rootDirectory.id else {
            throw FileScanningError.invalidRootDirectory
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        let fileName = fileURL.lastPathComponent
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // Get file attributes
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: filePath)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let createdAt = attributes[.creationDate] as? Date ?? Date()
        let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
        
        // Calculate relative path
        let relativePath = String(filePath.dropFirst(rootDirectory.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Fast scan: Check if file exists and hasn't changed
        if fastScan, let existingPhoto = existingPhotos[relativePath] {
            // Check if file size and modification date match
            if existingPhoto.fileSize == fileSize && existingPhoto.modifiedAt == modifiedAt {
                Self.logger.info("Fast scan: Skipping unchanged file \(fileName, privacy: .public)")
                return
            }
        }
        
        // Calculate file hash
        let fileHash = try await calculateFileHash(filePath: filePath)
        
        // Extract EXIF data
        let exifData = extractExifData(from: filePath)
        
        // Create PhotoFile object
        let photoFile = PhotoFile(
            id: nil,
            rootDirectoryId: rootDirectoryId,
            relativePath: relativePath,
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: fileSize,
            fileHash: fileHash,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            exifDateTaken: exifData.dateTaken,
            exifCameraModel: exifData.cameraModel,
            exifLensModel: exifData.lensModel,
            exifFocalLength: exifData.focalLength,
            exifAperture: exifData.aperture,
            exifIso: exifData.iso,
            exifShutterSpeed: exifData.shutterSpeed,
            imageWidth: exifData.imageWidth,
            imageHeight: exifData.imageHeight,
            hasThumbnail: false,
            thumbnailPath: nil,
            userDescription: nil,
            userTags: nil
        )
        
        // Save to database
        _ = try databaseManager.addPhotoFile(photoFile)
    }
    
    private func calculateFileHash(filePath: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    let hash = SHA256.hash(data: data)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hashString)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func extractExifData(from filePath: String) -> ExifData {
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: filePath) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return ExifData()
        }
        
        var exifData = ExifData()
        
        // Image dimensions
        if let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int {
            exifData.imageWidth = pixelWidth
        }
        if let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int {
            exifData.imageHeight = pixelHeight
        }
        
        // EXIF data
        if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            // Date taken
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                exifData.dateTaken = parseExifDate(dateString)
            }
            
            // Focal length
            if let focalLength = exifDict[kCGImagePropertyExifFocalLength as String] as? Double {
                exifData.focalLength = focalLength
            }
            
            // F-number (aperture)
            if let aperture = exifDict[kCGImagePropertyExifFNumber as String] as? Double {
                exifData.aperture = aperture
            }
            
            // ISO
            if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
               let isoValue = iso.first {
                exifData.iso = isoValue
            }
            
            // Shutter speed
            if let shutterSpeed = exifDict[kCGImagePropertyExifExposureTime as String] as? Double {
                exifData.shutterSpeed = formatShutterSpeed(shutterSpeed)
            }
            
            // Lens model
            exifData.lensModel = exifDict[kCGImagePropertyExifLensModel as String] as? String
        }
        
        // TIFF data for camera model
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiffDict[kCGImagePropertyTIFFMake as String] as? String,
               let model = tiffDict[kCGImagePropertyTIFFModel as String] as? String {
                exifData.cameraModel = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            } else if let model = tiffDict[kCGImagePropertyTIFFModel as String] as? String {
                exifData.cameraModel = model
            }
        }
        
        return exifData
    }
    
    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
    private func formatShutterSpeed(_ exposureTime: Double) -> String {
        if exposureTime >= 1 {
            return String(format: "%.1fs", exposureTime)
        } else {
            let denominator = Int(1.0 / exposureTime)
            return "1/\(denominator)s"
        }
    }
}

struct ExifData {
    var dateTaken: Date?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var iso: Int?
    var shutterSpeed: String?
    var imageWidth: Int?
    var imageHeight: Int?
}

enum FileScanningError: Error {
    case invalidRootDirectory
    case fileNotFound
    case hashCalculationFailed
}
