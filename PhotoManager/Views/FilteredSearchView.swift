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
    @Binding var selectedPhoto: PhotoFile?
    
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var filteredPhotos: [PhotoFile] = []
    @State private var thumbnailSize: CGFloat = 200
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with result count
            HStack {
                Text("Search Results")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(filteredPhotos.count) photos found")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    }
    
    private func performFilteredSearch() {
        logger.info("Performing filtered search")
        
        // Start with text search if provided
        var results: [PhotoFile] = []
        
        if !searchText.isEmpty {
            results = photoLibrary.searchPhotos(query: searchText)
            logger.info("Text search returned \(results.count) results")
        } else {
            // Get all photos from all directories
            for directory in photoLibrary.rootDirectories {
                if let directoryId = directory.id {
                    results.append(contentsOf: photoLibrary.getPhotosForDirectory(directoryId))
                }
            }
            logger.info("Loaded all \(results.count) photos for filtering")
        }
        
        // Apply date filter
        if let start = startDate {
            results = results.filter { photo in
                let photoDate = photo.exifDateTaken ?? photo.createdAt
                return photoDate >= start
            }
            logger.info("After start date filter: \(results.count) photos")
        }
        
        if let end = endDate {
            results = results.filter { photo in
                let photoDate = photo.exifDateTaken ?? photo.createdAt
                return photoDate <= end
            }
            logger.info("After end date filter: \(results.count) photos")
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
