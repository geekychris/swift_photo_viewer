import SwiftUI
import os.log
//foo
private let logger = Logger(subsystem: "com.photomarger", category: "photogrid")

struct PhotoGridView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedPhoto: PhotoFile?
    let filterDirectoryId: Int64?
    let filterSubdirectoryPath: String?
    @State private var photos: [PhotoFile] = []
    @State private var displayedPhotos: [PhotoFile] = []
    @State private var itemsPerPage = 50
    @State private var currentPage = 0
    @State private var thumbnailSize: CGFloat = 200
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                ForEach(displayedPhotos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        thumbnailSize: thumbnailSize,
                        onTap: {
                            selectedPhoto = photo
                        }
                    )
                    .onAppear {
                        if photo == displayedPhotos.last {
                            loadMorePhotos()
                        }
                    }
                }
                
                // Loading indicator
                if displayedPhotos.count < photos.count {
                    ProgressView()
                        .frame(width: 200, height: 200)
                        .onAppear {
                            loadMorePhotos()
                        }
                }
            }
            .padding()
            }
        }
        .onAppear {
            loadPhotos()
        }
        .onChange(of: photoLibrary.rootDirectories) {
            loadPhotos()
        }
        .onChange(of: filterDirectoryId) {
            loadPhotos()
        }
        .onChange(of: filterSubdirectoryPath) {
            loadPhotos()
        }
        .onChange(of: photoLibrary.thumbnailsUpdated) {
            logger.info("Thumbnails updated, reloading photos")
            loadPhotos()
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            // When detail view closes (selectedPhoto becomes nil), reload to get fresh data
            if newValue == nil && oldValue != nil {
                logger.info("Detail view closed, reloading photos to get fresh metadata")
                loadPhotos()
            }
        }
    }
    
    private func loadPhotos() {
        logger.info("Loading photos (filterDirectoryId: \(String(describing: filterDirectoryId), privacy: .public))")
        // Load photos based on filter
        var allPhotos: [PhotoFile] = []
        
        if let filterId = filterDirectoryId {
            // Load photos from specific directory
            logger.info("Loading photos from directory ID: \(filterId, privacy: .public), subdirectory: \(String(describing: filterSubdirectoryPath), privacy: .public)")
            var directoryPhotos = photoLibrary.getPhotosForDirectory(filterId)
            
            // If subdirectory is specified, filter to only that subdirectory and its children
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
                logger.info("Filtered to \(directoryPhotos.count, privacy: .public) photos in subdirectory: \(subdir, privacy: .public)")
            }
            
            allPhotos = directoryPhotos
            logger.info("Loaded \(allPhotos.count, privacy: .public) photos from directory ID: \(filterId, privacy: .public)")
        } else {
            // Load all photos from all directories
            logger.info("Loading photos from all \(photoLibrary.rootDirectories.count, privacy: .public) directories")
            for directory in photoLibrary.rootDirectories {
                if let directoryId = directory.id {
                    logger.info("Loading photos from directory: \(directory.name, privacy: .public) (ID: \(directoryId, privacy: .public))")
                    let directoryPhotos = photoLibrary.getPhotosForDirectory(directoryId)
                    allPhotos.append(contentsOf: directoryPhotos)
                    logger.info("Loaded \(directoryPhotos.count, privacy: .public) photos from \(directory.name, privacy: .public)")
                } else {
                    logger.warning("Directory \(directory.name, privacy: .public) has no ID")
                }
            }
            logger.info("Total photos loaded from all directories: \(allPhotos.count, privacy: .public)")
        }
        
        // Sort by EXIF date if available, otherwise by creation date
        photos = allPhotos.sorted { photo1, photo2 in
            let date1 = photo1.exifDateTaken ?? photo1.createdAt
            let date2 = photo2.exifDateTaken ?? photo2.createdAt
            return date1 > date2
        }
        
        logger.info("Sorted \(photos.count, privacy: .public) photos, resetting pagination")
        
        // Reset pagination
        currentPage = 0
        displayedPhotos = []
        loadMorePhotos()
        
        logger.info("After loadMorePhotos: displayedPhotos.count = \(displayedPhotos.count, privacy: .public)")
    }
    
    private func loadMorePhotos() {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, photos.count)
        
        if startIndex < photos.count {
            displayedPhotos.append(contentsOf: photos[startIndex..<endIndex])
            currentPage += 1
        }
    }
}

// MARK: - Rating Label Component
struct RatingPickerLabel: View {
    let rating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<rating, id: \.self) { _ in
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Color Tag Indicator Component
struct ColorTagIndicator: View {
    let colorTag: String?
    var size: CGFloat = 12
    
    private func colorForTag(_ tag: String) -> Color? {
        switch tag {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray": return .gray
        default: return nil
        }
    }
    
    var body: some View {
        if let colorTag = colorTag,
           let color = colorForTag(colorTag) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: PhotoFile
    let thumbnailSize: CGFloat
    let onTap: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var thumbnailImage: NSImage?
    @State private var isHovering: Bool = false
    @State private var rating: Int = 0
    @State private var colorTag: String? = nil
    @State private var refreshTrigger: Int = 0
    
    private var quickColors: [(id: String, color: Color)] {
        [
            ("red", .red),
            ("orange", .orange),
            ("yellow", .yellow),
            ("green", .green),
            ("blue", .blue),
            ("purple", .purple),
            ("gray", .gray)
        ]
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with overlay controls
            ZStack {
                Group {
                    if let thumbnailImage = thumbnailImage {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
                .cornerRadius(8)
                .onTapGesture {
                    onTap()
                }
                
                // Hover overlay with quick edit controls
                if isHovering {
                    VStack {
                        Spacer()
                        VStack(spacing: 6) {
                            // Quick rating picker
                            HStack(spacing: 3) {
                                ForEach(0..<6) { index in
                                Button {
                                    let newRating = rating == index ? 0 : index
                                    rating = newRating
                                    if let photoId = photo.id {
                                        photoLibrary.updatePhotoRating(photoId, rating: newRating)
                                        refreshTrigger += 1
                                    }
                                } label: {
                                        Image(systemName: index <= rating ? "flag.fill" : "flag")
                                            .foregroundColor(index <= rating ? .orange : .white.opacity(0.7))
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(index) flag\(index == 1 ? "" : "s")")
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                            
                            // Quick color picker
                            HStack(spacing: 4) {
                                // Clear button
                                Button {
                                    colorTag = nil
                                    if let photoId = photo.id {
                                        photoLibrary.updatePhotoColorTag(photoId, colorTag: nil)
                                        refreshTrigger += 1
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Clear color")
                                
                                ForEach(quickColors, id: \.id) { option in
                                    Button {
                                        let newColor = colorTag == option.id ? nil : option.id
                                        colorTag = newColor
                                        if let photoId = photo.id {
                                            photoLibrary.updatePhotoColorTag(photoId, colorTag: newColor)
                                            refreshTrigger += 1
                                        }
                                    } label: {
                                        ZStack {
                                            // Larger hit area
                                            Rectangle()
                                                .fill(Color.clear)
                                                .frame(width: 24, height: 24)
                                            
                                            Circle()
                                                .fill(option.color)
                                                .frame(width: 16, height: 16)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                                                )
                                                .overlay(
                                                    colorTag == option.id ?
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundColor(.white)
                                                    : nil
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(option.id.capitalized)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                        .padding(8)
                    }
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            
            // Photo info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Date and dimensions
                HStack {
                    if let dateTaken = photo.exifDateTaken {
                        Text(dateTaken, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let width = photo.imageWidth, let height = photo.imageHeight {
                        Text("\(width)×\(height)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Camera model
                if let cameraModel = photo.exifCameraModel {
                    Text(cameraModel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Exposure details
                if photo.exifAperture != nil || photo.exifShutterSpeed != nil || photo.exifIso != nil || photo.exifFocalLength != nil {
                    HStack(spacing: 4) {
                        if let aperture = photo.exifAperture {
                            Text("f/\(String(format: "%.1f", aperture))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let shutterSpeed = photo.exifShutterSpeed {
                            Text(shutterSpeed)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let iso = photo.exifIso {
                            Text("ISO\(iso)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let focalLength = photo.exifFocalLength {
                            Text("\(Int(focalLength))mm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Rating and Color Tag
                HStack(spacing: 6) {
                    // Rating - use state variable to show changes
                    if rating > 0 {
                        RatingPickerLabel(rating: rating)
                    }
                    
                    // Color Tag - use state variable to show changes
                    ColorTagIndicator(colorTag: colorTag, size: 10)
                }
                .id(refreshTrigger) // Force refresh when changed
                
                // User tags if available
                if let tags = photo.userTags, !tags.isEmpty {
                    Text(tags)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .help("Tags: \(tags)")
                }
                
                // User description if available
                if let description = photo.userDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                        .lineLimit(2)
                        .help(description)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: thumbnailSize, alignment: .leading)
        }
        .onAppear {
            loadThumbnail()
            rating = photo.rating
            colorTag = photo.colorTag
        }
        .onChange(of: photo.hasThumbnail) {
            loadThumbnail()
        }
        .onChange(of: photo.rating) { oldValue, newValue in
            rating = newValue
        }
        .onChange(of: photo.colorTag) { oldValue, newValue in
            colorTag = newValue
        }
        .id(photo.id) // Force view refresh when photo changes
    }
    
    private func loadThumbnail() {
        thumbnailImage = photoLibrary.getThumbnailImage(for: photo)
    }
}
