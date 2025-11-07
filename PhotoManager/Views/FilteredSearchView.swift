import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "filter")

struct FilteredSearchView: View {
    let searchText: String
    let startDate: Date?
    let endDate: Date?
    let camera: String
    let minAperture: Double?
    let maxAperture: Double?
    let minISO: Int?
    let maxISO: Int?
    let minRating: Int
    let selectedColors: Set<String>
    let filterDirectoryId: Int64?
    let filterSubdirectoryPath: String?
    let filterTimelinePeriod: String?
    @Binding var selectedPhoto: PhotoFile?
    
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var filteredPhotos: [PhotoFile] = []
    @State private var thumbnailSize: CGFloat = 200
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    private var searchContext: String? {
        if let directoryId = filterDirectoryId {
            if let directory = photoLibrary.rootDirectories.first(where: { $0.id == directoryId }) {
                if let subdir = filterSubdirectoryPath {
                    return "📁 \(directory.name) › \(subdir)"
                } else {
                    return "📁 \(directory.name)"
                }
            }
            return "📁 Directory"
        } else if let period = filterTimelinePeriod {
            // Format the period nicely
            let formatter = DateFormatter()
            if period.contains("W") {
                let parts = period.split(separator: "-")
                if parts.count == 2, let weekNum = parts[1].dropFirst().description as String? {
                    return "📅 Week \(weekNum), \(parts[0])"
                }
            } else if period.count == 10 {
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: period) {
                    formatter.dateFormat = "MMM d, yyyy"
                    return "📅 \(formatter.string(from: date))"
                }
            } else {
                formatter.dateFormat = "yyyy-MM"
                if let date = formatter.date(from: period) {
                    formatter.dateFormat = "MMMM yyyy"
                    return "📅 \(formatter.string(from: date))"
                }
            }
            return "📅 Timeline"
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with result count and context
            VStack(spacing: 4) {
                HStack {
                    Text("Search Results")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(filteredPhotos.count) photos found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let context = searchContext {
                    HStack {
                        Text("Searching in: \(context)")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Thumbnail size control
            HStack {
                Text("Thumbnail Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $thumbnailSize, in: 100...400, step: 50)
                    .frame(width: 200)
                
                Text("\(Int(thumbnailSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Results grid
            if filteredPhotos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    
                    Text("No photos found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Try adjusting your search criteria")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredPhotos) { photo in
                            PhotoThumbnailView(
                                photo: photo,
                                thumbnailSize: thumbnailSize,
                                onTap: {
                                    selectedPhoto = photo
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            performFilteredSearch()
        }
        .onChange(of: searchText) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: startDate) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: endDate) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: camera) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: minAperture) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: maxAperture) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: minISO) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: maxISO) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: minRating) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: selectedColors) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: filterDirectoryId) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: filterSubdirectoryPath) { _, _ in
            performFilteredSearch()
        }
        .onChange(of: filterTimelinePeriod) { _, _ in
            performFilteredSearch()
        }
    }
    
    private func performFilteredSearch() {
        logger.info("Performing filtered search")
        
        // Start with context-scoped photos
        var results: [PhotoFile] = []
        
        // Determine initial photo set based on context (directory, timeline, or all)
        if let directoryId = filterDirectoryId {
            // Directory view context
            var directoryPhotos = photoLibrary.getPhotosForDirectory(directoryId)
            
            // Apply subdirectory filter if specified
            if let subdir = filterSubdirectoryPath {
                directoryPhotos = directoryPhotos.filter { photo in
                    let pathComponents = photo.relativePath.split(separator: "/")
                    if pathComponents.count > 1 {
                        let firstComponent = String(pathComponents[0])
                        return firstComponent == subdir
                    } else {
                        return subdir == "Root"
                    }
                }
                logger.info("Scoped to subdirectory '\(subdir)': \(directoryPhotos.count) photos")
            }
            
            results = directoryPhotos
            logger.info("Scoped to directory \(directoryId): \(results.count) photos")
        } else if let timelinePeriod = filterTimelinePeriod {
            // Timeline view context
            for directory in photoLibrary.rootDirectories {
                if let directoryId = directory.id {
                    results.append(contentsOf: photoLibrary.getPhotosForDirectory(directoryId))
                }
            }
            
            // Filter by timeline period
            results = results.filter { photo in
                let photoDate = photo.exifDateTaken ?? photo.createdAt
                let formatter = DateFormatter()
                
                // Determine period format based on pattern
                if timelinePeriod.contains("W") {
                    // Weekly format: "yyyy-Www"
                    formatter.dateFormat = "yyyy"
                    let calendar = Calendar.current
                    let year = formatter.string(from: photoDate)
                    let weekOfYear = calendar.component(.weekOfYear, from: photoDate)
                    let photoWeek = String(format: "%@-W%02d", year, weekOfYear)
                    return photoWeek == timelinePeriod
                } else if timelinePeriod.count == 10 {
                    // Daily format: "yyyy-MM-dd"
                    formatter.dateFormat = "yyyy-MM-dd"
                    return formatter.string(from: photoDate) == timelinePeriod
                } else {
                    // Monthly format: "yyyy-MM"
                    formatter.dateFormat = "yyyy-MM"
                    return formatter.string(from: photoDate) == timelinePeriod
                }
            }
            logger.info("Scoped to timeline period '\(timelinePeriod)': \(results.count) photos")
        } else {
            // No specific context - search all photos
            for directory in photoLibrary.rootDirectories {
                if let directoryId = directory.id {
                    results.append(contentsOf: photoLibrary.getPhotosForDirectory(directoryId))
                }
            }
            logger.info("No scope filter - loaded all \(results.count) photos")
        }
        
        // Now apply text search filter if provided
        if !searchText.isEmpty {
            results = results.filter { photo in
                // Search in filename, description, and tags
                let filename = photo.fileName.lowercased()
                let description = (photo.userDescription ?? "").lowercased()
                let tags = (photo.userTags ?? "").lowercased()
                let searchLower = searchText.lowercased()
                
                return filename.contains(searchLower) ||
                       description.contains(searchLower) ||
                       tags.contains(searchLower)
            }
            logger.info("After text search: \(results.count) photos")
        }
        
        // Apply date filter
        if let start = startDate {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: start)
            results = results.filter { photo in
                let photoDate = photo.exifDateTaken ?? photo.createdAt
                return photoDate >= startOfDay
            }
            logger.info("After start date filter (\(start)): \(results.count) photos")
        }
        
        if let end = endDate {
            let calendar = Calendar.current
            // End of the selected day (23:59:59)
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            results = results.filter { photo in
                let photoDate = photo.exifDateTaken ?? photo.createdAt
                return photoDate <= endOfDay
            }
            logger.info("After end date filter (\(end)): \(results.count) photos")
        }
        
        // Apply camera filter
        if !camera.isEmpty {
            results = results.filter { photo in
                guard let cameraModel = photo.exifCameraModel else { return false }
                return cameraModel.localizedCaseInsensitiveContains(camera)
            }
            logger.info("After camera filter: \(results.count) photos")
        }
        
        // Apply aperture filter
        if let minAp = minAperture {
            results = results.filter { photo in
                guard let aperture = photo.exifAperture else { return false }
                return aperture >= minAp
            }
            logger.info("After min aperture filter: \(results.count) photos")
        }
        
        if let maxAp = maxAperture {
            results = results.filter { photo in
                guard let aperture = photo.exifAperture else { return false }
                return aperture <= maxAp
            }
            logger.info("After max aperture filter: \(results.count) photos")
        }
        
        // Apply ISO filter
        if let minIso = minISO {
            results = results.filter { photo in
                guard let iso = photo.exifIso else { return false }
                return iso >= minIso
            }
            logger.info("After min ISO filter: \(results.count) photos")
        }
        
        if let maxIso = maxISO {
            results = results.filter { photo in
                guard let iso = photo.exifIso else { return false }
                return iso <= maxIso
            }
            logger.info("After max ISO filter: \(results.count) photos")
        }
        
        // Apply rating filter (at least minRating)
        if minRating > 0 {
            results = results.filter { photo in
                photo.rating >= minRating
            }
            logger.info("After rating filter: \(results.count) photos")
        }
        
        // Apply color filter (any of selected colors)
        if !selectedColors.isEmpty {
            results = results.filter { photo in
                guard let colorTag = photo.colorTag else { return false }
                return selectedColors.contains(colorTag)
            }
            logger.info("After color filter: \(results.count) photos")
        }
        
        // Sort by date
        filteredPhotos = results.sorted { photo1, photo2 in
            let date1 = photo1.exifDateTaken ?? photo1.createdAt
            let date2 = photo2.exifDateTaken ?? photo2.createdAt
            return date1 > date2
        }
        
        logger.info("Final filtered results: \(filteredPhotos.count) photos")
    }
}
