import SwiftUI
import os.log
import AppKit
//foo
private let logger = Logger(subsystem: "com.photomarger", category: "photogrid")

// MARK: - Destination Type

enum Destination: Equatable {
    case managedDirectory(RootDirectory)
    case unmanagedURL(URL) // Store URL to maintain security-scoped access
    
    static func ==(lhs: Destination, rhs: Destination) -> Bool {
        switch (lhs, rhs) {
        case (.managedDirectory(let a), .managedDirectory(let b)):
            return a.id == b.id
        case (.unmanagedURL(let a), .unmanagedURL(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum ContactSheetFormat {
    case html
    case pdf
}

struct ContactSheetOptions: Equatable {
    var format: ContactSheetFormat
    var includeFilePath: Bool = true
    var includeFileName: Bool = true
    var includeDate: Bool = true
    var includeDimensions: Bool = true
    var includeFileSize: Bool = true
    var includeCamera: Bool = true
    var includeLens: Bool = true
    var includeExposure: Bool = true
    var includeDescription: Bool = true
    var includeTags: Bool = true
}

struct ContactSheetOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var options: ContactSheetOptions?
    let format: ContactSheetFormat
    let photoCount: Int
    
    @State private var localOptions: ContactSheetOptions
    
    init(options: Binding<ContactSheetOptions?>, format: ContactSheetFormat, photoCount: Int) {
        self._options = options
        self.format = format
        self.photoCount = photoCount
        self._localOptions = State(initialValue: ContactSheetOptions(format: format))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Contact Sheet Options")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            // Options
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select metadata to include in \(format == .html ? "HTML" : "PDF") contact sheet (\(photoCount) photos):")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("File Path", isOn: $localOptions.includeFilePath)
                        Toggle("File Name", isOn: $localOptions.includeFileName)
                        Toggle("Date Taken", isOn: $localOptions.includeDate)
                        Toggle("Image Dimensions", isOn: $localOptions.includeDimensions)
                        Toggle("File Size", isOn: $localOptions.includeFileSize)
                        Toggle("Camera Model", isOn: $localOptions.includeCamera)
                        Toggle("Lens Model", isOn: $localOptions.includeLens)
                        Toggle("Exposure Settings (Aperture, Shutter, ISO, Focal Length)", isOn: $localOptions.includeExposure)
                        Toggle("User Description", isOn: $localOptions.includeDescription)
                        Toggle("User Tags", isOn: $localOptions.includeTags)
                    }
                    .toggleStyle(.checkbox)
                    
                    Divider()
                    
                    HStack {
                        Button("Select All") {
                            localOptions.includeFilePath = true
                            localOptions.includeFileName = true
                            localOptions.includeDate = true
                            localOptions.includeDimensions = true
                            localOptions.includeFileSize = true
                            localOptions.includeCamera = true
                            localOptions.includeLens = true
                            localOptions.includeExposure = true
                            localOptions.includeDescription = true
                            localOptions.includeTags = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Deselect All") {
                            localOptions.includeFilePath = false
                            localOptions.includeFileName = false
                            localOptions.includeDate = false
                            localOptions.includeDimensions = false
                            localOptions.includeFileSize = false
                            localOptions.includeCamera = false
                            localOptions.includeLens = false
                            localOptions.includeExposure = false
                            localOptions.includeDescription = false
                            localOptions.includeTags = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate") {
                    options = localOptions
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }
}

// MARK: - Destination Picker View

struct DestinationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedDestination: Destination?
    
    let operationType: OperationType
    let photoCount: Int
    
    @State private var showingFilePicker = false
    @State private var selectedDirectory: RootDirectory?
    
    enum OperationType {
        case copy
        case move
        
        var title: String {
            switch self {
            case .copy: return "Copy"
            case .move: return "Move"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(operationType.title) \(photoCount) photo\(photoCount == 1 ? "" : "s")")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Select destination:").font(.headline)
                
                if !photoLibrary.rootDirectories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Managed Directories").font(.subheadline).foregroundColor(.secondary)
                        
                        ForEach(photoLibrary.rootDirectories) { directory in
                            Button {
                                selectedDirectory = directory
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill").foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(directory.name).fontWeight(.medium)
                                        Text(directory.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedDirectory?.id == directory.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                    }
                                }
                                .padding(12)
                                .background(selectedDirectory?.id == directory.id ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().padding(.vertical, 8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Location").font(.subheadline).foregroundColor(.secondary)
                    Button { showingFilePicker = true } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus").foregroundColor(.green)
                            Text("Choose a folder...").fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            Spacer()
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(operationType.title) {
                    if let directory = selectedDirectory {
                        selectedDestination = .managedDirectory(directory)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDirectory == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                print("📂 File picker selected: \(url.path), accessing: \(accessing)")
                selectedDestination = .unmanagedURL(url)
                dismiss()
            }
        }
    }
}

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
    @State private var selectedPhotoIds: Set<Int64> = []
    @State private var isSelectionMode: Bool = false
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack {
                // Selection mode toggle
                Button {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedPhotoIds.removeAll()
                    }
                } label: {
                    Label(isSelectionMode ? "Cancel" : "Select", systemImage: isSelectionMode ? "xmark.circle" : "checkmark.circle")
                }
                .buttonStyle(.bordered)
                
                if isSelectionMode {
                    Button("Select All") {
                        selectedPhotoIds = Set(displayedPhotos.compactMap { $0.id })
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Deselect All") {
                        selectedPhotoIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPhotoIds.isEmpty)
                    
                    Text("\(selectedPhotoIds.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
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
                        isSelectionMode: isSelectionMode,
                        isSelected: photo.id.map { selectedPhotoIds.contains($0) } ?? false,
                        onTap: {
                            if isSelectionMode {
                                if let photoId = photo.id {
                                    if selectedPhotoIds.contains(photoId) {
                                        selectedPhotoIds.remove(photoId)
                                    } else {
                                        selectedPhotoIds.insert(photoId)
                                    }
                                }
                            } else {
                                selectedPhoto = photo
                            }
                        },
                        selectedPhotoIds: $selectedPhotoIds
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
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    var selectedPhotoIds: Binding<Set<Int64>>? = nil
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var thumbnailImage: NSImage?
    @State private var isHovering: Bool = false
    @State private var rating: Int = 0
    @State private var colorTag: String? = nil
    @State private var refreshTrigger: Int = 0
    @State private var showingDestinationPicker: Bool = false
    @State private var destinationPickerType: DestinationPickerView.OperationType = .copy
    @State private var selectedDestination: Destination? = nil
    @State private var showingProgressAlert: Bool = false
    @State private var operationMessage: String = ""
    @State private var showingContactSheetOptions: Bool = false
    @State private var contactSheetOptions: ContactSheetOptions? = nil
    
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
    
    @ViewBuilder
    private var thumbnailDisplay: some View {
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
    }
    
    @ViewBuilder
    private var hoverControls: some View {
        if isHovering && !isSelectionMode {
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { index in
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
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    
                    HStack(spacing: 4) {
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
                                    Rectangle().fill(Color.clear).frame(width: 24, height: 24)
                                    Circle().fill(option.color).frame(width: 16, height: 16)
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                                        .overlay(colorTag == option.id ? Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white) : nil)
                                }
                            }
                            .buttonStyle(.plain)
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
    
    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with overlay controls
            ZStack {
                thumbnailDisplay
                
                // Selection indicator
                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(isSelected ? .blue : .white)
                            }
                            .padding(8)
                        }
                        Spacer()
                    }
                }
                
                hoverControls
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .contextMenu {
                if let photoId = photo.id {
                    Button {
                        openWithDefaultApp()
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    
                    Divider()
                    
                    Menu("Contact Sheet") {
                        Button {
                            showContactSheetOptionsFor(format: .html)
                        } label: {
                            Label("HTML", systemImage: "doc.richtext")
                        }
                        
                        Button {
                            showContactSheetOptionsFor(format: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.fill")
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        copyFiles()
                    } label: {
                        Label("Copy to...", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        moveFiles()
                    } label: {
                        Label("Move to...", systemImage: "folder")
                    }
                }
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
        .onChange(of: selectedDestination) { _, newValue in
            if newValue != nil {
                performFileOperation()
            }
        }
        .sheet(isPresented: $showingDestinationPicker) {
            DestinationPickerView(
                selectedDestination: $selectedDestination,
                operationType: destinationPickerType,
                photoCount: getSelectedPhotos().count
            )
        }
        .sheet(isPresented: $showingContactSheetOptions) {
            if let options = contactSheetOptions {
                ContactSheetOptionsView(
                    options: $contactSheetOptions,
                    format: options.format,
                    photoCount: getSelectedPhotos().count
                )
            }
        }
        .onChange(of: contactSheetOptions) { oldValue, newValue in
            if let options = newValue, oldValue == nil || oldValue!.format != options.format {
                generateContactSheet(with: options)
                contactSheetOptions = nil
            }
        }
        .alert(operationMessage, isPresented: $showingProgressAlert) {
            Button("OK") {
                showingProgressAlert = false
            }
        }
        .id(photo.id) // Force view refresh when photo changes
    }
    
    private func getSelectedPhotos() -> [PhotoFile] {
        guard let selectedIds = selectedPhotoIds else {
            // No binding provided, use current photo
            return [photo]
        }
        
        if selectedIds.wrappedValue.isEmpty {
            // No selection, use current photo
            return [photo]
        } else {
            // Use selection
            let allPhotos = photoLibrary.rootDirectories.flatMap { directory -> [PhotoFile] in
                guard let directoryId = directory.id else { return [] }
                return photoLibrary.getPhotosForDirectory(directoryId)
            }
            return allPhotos.filter { photo in
                guard let photoId = photo.id else { return false }
                return selectedIds.wrappedValue.contains(photoId)
            }
        }
    }
    
    private func showContactSheetOptionsFor(format: ContactSheetFormat) {
        contactSheetOptions = ContactSheetOptions(format: format)
        showingContactSheetOptions = true
    }
    
    private func openWithDefaultApp() {
        let photos = getSelectedPhotos()
        for photo in photos {
            guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
                continue
            }
            
            let fullPath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
            let url = URL(fileURLWithPath: fullPath)
            
            // Try to restore security-scoped access
            if let bookmarkData = rootDirectory.bookmarkData {
                do {
                    var isStale = false
                    let directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                              options: [.withSecurityScope],
                                              relativeTo: nil,
                                              bookmarkDataIsStale: &isStale)
                    
                    if directoryURL.startAccessingSecurityScopedResource() {
                        NSWorkspace.shared.open(url)
                        directoryURL.stopAccessingSecurityScopedResource()
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                } catch {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func generateContactSheet(with options: ContactSheetOptions) {
        let photos = getSelectedPhotos()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = FileManager.default.temporaryDirectory
            let timestamp = Int(Date().timeIntervalSince1970)
            
            if options.format == .html {
                let exportDir = tempDir.appendingPathComponent("ContactSheet_\(timestamp)")
                let imagesDir = exportDir.appendingPathComponent("images")
                
                do {
                    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                    
                    var html = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Contact Sheet</title><style>body{font-family:system-ui;margin:20px;background:#f5f5f5}h1{text-align:center}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:20px}.card{background:white;border-radius:8px;padding:15px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}.card img{width:100%;height:300px;object-fit:cover;border-radius:4px}.info{margin-top:10px;font-size:0.85em;color:#333;line-height:1.5}.filename{font-weight:bold;font-size:1.1em;margin-bottom:8px}.path{font-size:0.8em;color:#666;font-family:monospace;word-break:break-all;margin:6px 0}.description{font-style:italic;color:#555;margin:8px 0;padding:8px;background:#f9f9f9;border-radius:4px}.date{color:#007aff;font-weight:500}</style></head><body><h1>Contact Sheet</h1><p style="text-align:center">\(photos.count) photos - Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))</p><div class="grid">
"""
                    
                    for (index, photo) in photos.enumerated() {
                        if let thumbnail = self.photoLibrary.getThumbnailImage(for: photo),
                           let tiffData = thumbnail.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) {
                            let imageName = "photo_\(index).jpg"
                            try? jpegData.write(to: imagesDir.appendingPathComponent(imageName))
                            
                            // Get full path
                            var fullPath = ""
                            if let rootDir = self.photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) {
                                fullPath = (rootDir.path as NSString).appendingPathComponent(photo.relativePath)
                            }
                            
                            html += "<div class=\"card\"><img src=\"images/\(imageName)\"><div class=\"info\">"
                            
                            // Full path (at top)
                            if options.includeFilePath && !fullPath.isEmpty {
                                html += "<div class=\"path\">📁 \(fullPath)</div>"
                            }
                            
                            // Filename
                            if options.includeFileName {
                                html += "<div class=\"filename\">\(photo.fileName)</div>"
                            }
                            
                            // Date
                            if options.includeDate, let dateTaken = photo.exifDateTaken {
                                let dateStr = DateFormatter.localizedString(from: dateTaken, dateStyle: .medium, timeStyle: .short)
                                html += "<div class=\"date\">📅 \(dateStr)</div>"
                            }
                            
                            // Dimensions and file size
                            var techInfo = ""
                            if options.includeDimensions, let width = photo.imageWidth, let height = photo.imageHeight {
                                techInfo += "📐 \(width) × \(height)"
                            }
                            if options.includeFileSize {
                                let sizeInMB = Double(photo.fileSize) / (1024 * 1024)
                                if !techInfo.isEmpty { techInfo += " " }
                                techInfo += String(format: "%.1fMB", sizeInMB)
                            }
                            if !techInfo.isEmpty {
                                html += "<div>\(techInfo)</div>"
                            }
                            
                            // Camera
                            if options.includeCamera, let camera = photo.exifCameraModel {
                                html += "<div>📷 \(camera)</div>"
                            }
                            
                            // Lens
                            if options.includeLens, let lens = photo.exifLensModel {
                                html += "<div>\(lens)</div>"
                            }
                            
                            // Exposure settings
                            if options.includeExposure {
                                var exposureInfo = ""
                                if let aperture = photo.exifAperture {
                                    exposureInfo = String(format: "f/%.1f", aperture)
                                }
                                if let shutter = photo.exifShutterSpeed {
                                    if !exposureInfo.isEmpty { exposureInfo += " " }
                                    exposureInfo += shutter
                                }
                                if let iso = photo.exifIso {
                                    if !exposureInfo.isEmpty { exposureInfo += " " }
                                    exposureInfo += "ISO\(iso)"
                                }
                                if let focal = photo.exifFocalLength {
                                    if !exposureInfo.isEmpty { exposureInfo += " " }
                                    exposureInfo += "\(Int(focal))mm"
                                }
                                if !exposureInfo.isEmpty {
                                    html += "<div>\(exposureInfo)</div>"
                                }
                            }
                            
                            // User description
                            if options.includeDescription, let desc = photo.userDescription, !desc.isEmpty {
                                let escaped = desc.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                                html += "<div class=\"description\">\(escaped)</div>"
                            }
                            
                            // Tags
                            if options.includeTags, let tags = photo.userTags, !tags.isEmpty {
                                html += "<div>🏷️ \(tags)</div>"
                            }
                            
                            html += "</div></div>"
                        }
                    }
                    
                    html += "</div></body></html>"
                    let htmlFile = exportDir.appendingPathComponent("index.html")
                    try html.write(to: htmlFile, atomically: true, encoding: .utf8)
                    
                    // Create zip file
                    let zipURL = tempDir.appendingPathComponent("ContactSheet_\(timestamp).zip")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", exportDir.path, zipURL.path]
                    try process.run()
                    process.waitUntilExit()
                    
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(zipURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.operationMessage = "Failed to generate HTML: \(error.localizedDescription)"
                        self.showingProgressAlert = true
                    }
                }
            } else {
                // PDF generation with thumbnails
                let pdfURL = tempDir.appendingPathComponent("ContactSheet_\(timestamp).pdf")
                let pageSize = CGSize(width: 612, height: 792)
                let margin: CGFloat = 40
                let columns = 3
                let spacing: CGFloat = 15
                let contentWidth = pageSize.width - (margin * 2)
                let thumbWidth = (contentWidth - (spacing * CGFloat(columns - 1))) / CGFloat(columns)
                let thumbHeight = thumbWidth * 0.75
                let cellHeight = thumbHeight + 140
                
                guard let pdfContext = CGContext(pdfURL as CFURL, mediaBox: nil, nil) else {
                    DispatchQueue.main.async {
                        self.operationMessage = "Failed to create PDF context"
                        self.showingProgressAlert = true
                    }
                    return
                }
                
                var yPosition = pageSize.height - margin
                var column = 0
                var needsNewPage = false
                
                // Title page
                pdfContext.beginPDFPage(nil)
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.black]
                let title = "Contact Sheet" as NSString
                title.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 30), withAttributes: titleAttrs)
                
                let subtitleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray]
                let subtitle = "\(photos.count) photos - Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))" as NSString
                subtitle.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 55), withAttributes: subtitleAttrs)
                
                yPosition = pageSize.height - margin - 100
                
                // Draw thumbnails
                for photo in photos {
                    // Check if we need a new page
                    if yPosition - cellHeight < margin {
                        pdfContext.endPDFPage()
                        pdfContext.beginPDFPage(nil)
                        yPosition = pageSize.height - margin
                        column = 0
                    }
                    
                    let xPosition = margin + (CGFloat(column) * (thumbWidth + spacing))
                    
                    // Helper function to draw text in PDF using NSGraphicsContext
                    func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
                        pdfContext.saveGState()
                        let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = nsContext
                        
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: color
                        ]
                        (text as NSString).draw(at: point, withAttributes: attrs)
                        
                        NSGraphicsContext.restoreGraphicsState()
                        pdfContext.restoreGState()
                    }
                    
                    var currentY = yPosition
                    let regularFont = NSFont.systemFont(ofSize: 6.5)
                    let boldFont = NSFont.boldSystemFont(ofSize: 8)
                    let tinyFont = NSFont.systemFont(ofSize: 5.5)
                    
                    // Full file path at top (in smaller font)
                    if options.includeFilePath, let rootDir = self.photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) {
                        let fullPath = (rootDir.path as NSString).appendingPathComponent(photo.relativePath)
                        // Split path into multiple lines if too long
                        if fullPath.count > 50 {
                            let parts = fullPath.split(separator: "/").map(String.init)
                            var pathLine = "/"
                            for part in parts {
                                if (pathLine + part).count > 50 {
                                    drawText(pathLine, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                                    currentY -= 7
                                    pathLine = "/" + part + "/"
                                } else {
                                    pathLine += part + "/"
                                }
                            }
                            if !pathLine.isEmpty && pathLine != "/" {
                                drawText(pathLine, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                                currentY -= 7
                            }
                        } else {
                            drawText(fullPath, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                            currentY -= 7
                        }
                        currentY -= 2 // Extra spacing after path
                    }
                    
                    // Filename
                    if options.includeFileName {
                        drawText(photo.fileName, at: CGPoint(x: xPosition, y: currentY), font: boldFont, color: .black)
                        currentY -= 9
                    }
                    
                    // Date and time
                    if options.includeDate, let dateTaken = photo.exifDateTaken {
                        let dateStr = DateFormatter.localizedString(from: dateTaken, dateStyle: .short, timeStyle: .short)
                        drawText(dateStr, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                        currentY -= 8
                    }
                    
                    // Dimensions and file size
                    var techInfo = ""
                    if options.includeDimensions, let width = photo.imageWidth, let height = photo.imageHeight {
                        techInfo = "\(width)×\(height)"
                    }
                    if options.includeFileSize {
                        let sizeInMB = Double(photo.fileSize) / (1024 * 1024)
                        if !techInfo.isEmpty { techInfo += " " }
                        techInfo += String(format: "%.1fMB", sizeInMB)
                    }
                    if !techInfo.isEmpty {
                        drawText(techInfo, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                        currentY -= 8
                    }
                    
                    // Camera and lens
                    if options.includeCamera, let camera = photo.exifCameraModel {
                        drawText(camera, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .darkGray)
                        currentY -= 8
                    }
                    if options.includeLens, let lens = photo.exifLensModel {
                        drawText(lens, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .darkGray)
                        currentY -= 8
                    }
                    
                    // Exposure settings
                    if options.includeExposure {
                        var exposureInfo = ""
                        if let aperture = photo.exifAperture {
                            exposureInfo = String(format: "f/%.1f", aperture)
                        }
                        if let shutter = photo.exifShutterSpeed {
                            if !exposureInfo.isEmpty { exposureInfo += " " }
                            exposureInfo += shutter
                        }
                        if let iso = photo.exifIso {
                            if !exposureInfo.isEmpty { exposureInfo += " " }
                            exposureInfo += "ISO\(iso)"
                        }
                        if let focal = photo.exifFocalLength {
                            if !exposureInfo.isEmpty { exposureInfo += " " }
                            exposureInfo += "\(Int(focal))mm"
                        }
                        if !exposureInfo.isEmpty {
                            drawText(exposureInfo, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                            currentY -= 8
                        }
                    }
                    
                    // Draw thumbnail
                    currentY -= 3
                    let imageRect = CGRect(x: xPosition, y: currentY - thumbHeight, width: thumbWidth, height: thumbHeight)
                    
                    if let thumbnail = self.photoLibrary.getThumbnailImage(for: photo) {
                        pdfContext.saveGState()
                        let ctx = NSGraphicsContext(cgContext: pdfContext, flipped: false)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = ctx
                        thumbnail.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1.0)
                        NSGraphicsContext.restoreGraphicsState()
                        pdfContext.restoreGState()
                    } else {
                        pdfContext.setFillColor(NSColor.lightGray.cgColor)
                        pdfContext.fill(imageRect)
                    }
                    
                    // Border
                    pdfContext.setStrokeColor(NSColor.gray.cgColor)
                    pdfContext.setLineWidth(0.5)
                    pdfContext.stroke(imageRect)
                    
                    currentY = imageRect.minY - 3
                    
                    // Description below image
                    if options.includeDescription, let desc = photo.userDescription, !desc.isEmpty {
                        let descText = desc.count > 45 ? String(desc.prefix(45)) + "..." : desc
                        drawText(descText, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                        currentY -= 9
                    }
                    
                    // Tags
                    if options.includeTags, let tags = photo.userTags, !tags.isEmpty {
                        drawText("🏷️ \(tags)", at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                        currentY -= 9
                    }
                    
                    column += 1
                    if column >= columns {
                        column = 0
                        yPosition -= cellHeight + spacing
                    }
                }
                
                pdfContext.endPDFPage()
                pdfContext.closePDF()
                
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(pdfURL)
                }
            }
        }
    }
    
    private func copyFiles() {
        destinationPickerType = .copy
        showingDestinationPicker = true
    }
    
    private func moveFiles() {
        destinationPickerType = .move
        showingDestinationPicker = true
    }
    
    private func performFileOperation() {
        guard let destination = selectedDestination else { return }
        
        let photos = getSelectedPhotos()
        let isCopy = destinationPickerType == .copy
        
        // Keep reference to unmanaged URL if present to stop accessing at the end
        var unmanagedDestURL: URL?
        if case .unmanagedURL(let url) = destination {
            unmanagedDestURL = url
        }
        
        operationMessage = "\(isCopy ? "Copying" : "Moving") \(photos.count) file\(photos.count == 1 ? "" : "s")..."
        showingProgressAlert = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("\n🚀 Starting file operation: \(isCopy ? "COPY" : "MOVE")")
            print("📊 Processing \(photos.count) files")
            print("🎯 Destination: \(destination)")
            
            var successCount = 0
            var errors: [String] = []
            
            for (index, photo) in photos.enumerated() {
                print("\n--- Processing file \(index + 1)/\(photos.count) ---")
                guard let rootDirectory = self.photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
                    errors.append("Root directory not found for \(photo.fileName)")
                    print("❌ Root directory not found for photo \(photo.fileName)")
                    continue
                }
                
                let sourcePath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
                let sourceURL = URL(fileURLWithPath: sourcePath)
                print("📁 Source: \(sourcePath)")
                
                // Check if source exists
                let sourceExists = FileManager.default.fileExists(atPath: sourcePath)
                print("🔍 Source exists: \(sourceExists)")
                
                guard sourceExists else {
                    errors.append("Source file not found: \(photo.fileName)")
                    print("❌ Source file not found: \(sourcePath)")
                    continue
                }
                
                // Restore security-scoped access for source directory
                var sourceAccessURL: URL?
                if let bookmarkData = rootDirectory.bookmarkData {
                    do {
                        var isStale = false
                        sourceAccessURL = try URL(resolvingBookmarkData: bookmarkData,
                                                 options: [.withSecurityScope],
                                                 relativeTo: nil,
                                                 bookmarkDataIsStale: &isStale)
                        if let url = sourceAccessURL {
                            _ = url.startAccessingSecurityScopedResource()
                            print("🔓 Started accessing source: \(url.path)")
                        }
                    } catch {
                        print("⚠️ Could not resolve source bookmark: \(error.localizedDescription)")
                    }
                }
                
                let destPath: String
                var destAccessURL: URL?
                switch destination {
                case .managedDirectory(let directory):
                    destPath = (directory.path as NSString).appendingPathComponent(photo.fileName)
                    // Restore security-scoped access for destination directory
                    if let bookmarkData = directory.bookmarkData {
                        do {
                            var isStale = false
                            destAccessURL = try URL(resolvingBookmarkData: bookmarkData,
                                                   options: [.withSecurityScope],
                                                   relativeTo: nil,
                                                   bookmarkDataIsStale: &isStale)
                            if let url = destAccessURL {
                                _ = url.startAccessingSecurityScopedResource()
                                print("🔓 Started accessing managed destination: \(url.path)")
                            }
                        } catch {
                            print("⚠️ Could not resolve destination bookmark: \(error.localizedDescription)")
                        }
                    }
                case .unmanagedURL(let url):
                    destPath = (url.path as NSString).appendingPathComponent(photo.fileName)
                    destAccessURL = url
                    // For unmanaged URLs from file picker, security scope should already be active
                    print("🔓 Using unmanaged destination (security scope active): \(url.path)")
                }
                
                let destURL = URL(fileURLWithPath: destPath)
                print("📋 \(isCopy ? "Copying" : "Moving"): \(sourcePath) -> \(destPath)")
                print("📂 Destination directory exists: \(FileManager.default.fileExists(atPath: (destPath as NSString).deletingLastPathComponent))")
                
                do {
                    // Check if destination already exists
                    if FileManager.default.fileExists(atPath: destPath) {
                        print("⚠️ Destination exists, removing: \(destPath)")
                        try FileManager.default.removeItem(at: destURL)
                    }
                    
                    print("⏳ Attempting \(isCopy ? "copy" : "move")...")
                    if isCopy {
                        try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    } else {
                        try FileManager.default.moveItem(at: sourceURL, to: destURL)
                    }
                    
                    // Verify the operation succeeded
                    let destExists = FileManager.default.fileExists(atPath: destPath)
                    print("🔍 Destination file exists after operation: \(destExists)")
                    
                    if destExists {
                        print("✅ Success: \(photo.fileName)")
                        successCount += 1
                    } else {
                        let errMsg = "\(photo.fileName): File operation completed but destination file not found"
                        errors.append(errMsg)
                        print("❌ \(errMsg)")
                    }
                } catch {
                    let errMsg = "\(photo.fileName): \(error.localizedDescription)"
                    errors.append(errMsg)
                    print("❌ Error caught: \(errMsg)")
                    print("❌ Error details: \(error)")
                }
                
                // Stop accessing security-scoped resources (only for managed directories)
                if let url = sourceAccessURL {
                    url.stopAccessingSecurityScopedResource()
                    print("🔒 Stopped accessing source")
                }
                // Don't stop access for unmanaged URLs - they need to stay active for the whole operation
                if let url = destAccessURL, case .managedDirectory = destination {
                    url.stopAccessingSecurityScopedResource()
                    print("🔒 Stopped accessing destination")
                }
            }
            
            // Stop accessing unmanaged URL after all operations complete
            if let url = unmanagedDestURL {
                url.stopAccessingSecurityScopedResource()
                print("🔒 Stopped accessing unmanaged destination")
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    var msg = "Successfully \(isCopy ? "copied" : "moved") \(successCount) file\(successCount == 1 ? "" : "s")"
                    if !errors.isEmpty {
                        msg += " (\(errors.count) failed)"
                    }
                    self.operationMessage = msg
                    // Reload to reflect changes
                    self.photoLibrary.loadRootDirectories()
                } else if !errors.isEmpty {
                    self.operationMessage = "Failed: \(errors.first ?? "Unknown error")"
                    print("❌ All operations failed. Errors: \(errors.joined(separator: ", "))")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showingProgressAlert = false
                    self.selectedDestination = nil
                }
            }
        }
    }
    
    private func loadThumbnail() {
        thumbnailImage = photoLibrary.getThumbnailImage(for: photo)
    }
}
