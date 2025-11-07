import SwiftUI
//foo
struct PhotoDetailView: View {
    let photo: PhotoFile
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var userDescription: String = ""
    @State private var userTags: String = ""
    @State private var rating: Int = 0
    @State private var colorTag: String? = nil
    @State private var hasUnsavedChanges = false
    @State private var showingFullscreenImage = false
    @State private var showingSaveSuccess = false
    @State private var currentPhotoId: Int64?
    @State private var showingOpenWithPicker = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Image display - takes most of the space
            ZStack {
                if let fullImage = fullImage {
                    Image(nsImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.05))
                        .onTapGesture {
                            showingFullscreenImage = true
                        }
                        .contextMenu {
                            Button(action: { openWithDefaultApp() }) {
                                Label("Open", systemImage: "arrow.up.forward.app")
                            }
                            Button(action: { showingOpenWithPicker = true }) {
                                Label("Open With...", systemImage: "ellipsis.circle")
                            }
                            Divider()
                            Button(action: showInFinder) {
                                Label("Show in Finder", systemImage: "folder")
                            }
                        }
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                } else if isLoading {
                    ProgressView("Loading image...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)
                        
                        Text("Unable to load image")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Click indicator overlay
                if fullImage != nil && !isLoading {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Click to view fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .padding()
                        }
                    }
                }
            }
            
            Divider()
            
            // EXIF and metadata panel
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // User metadata
                        MetadataSectionView(title: "Description & Tags") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Description")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    SpeechInputButton(text: $userDescription)
                                }
                                
                                TextEditor(text: $userDescription)
                                    .frame(height: 80)
                                    .font(.body)
                                    .border(Color.gray.opacity(0.3))
                                    .onChange(of: userDescription) {
                                        hasUnsavedChanges = true
                                    }
                                
                                Text("Tags (comma-separated)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                
                                TextField("Enter tags", text: $userTags)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: userTags) {
                                        hasUnsavedChanges = true
                                    }
                                
                                HStack {
                                    if hasUnsavedChanges {
                                        Button("Save") {
                                            saveMetadata()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    
                                    if showingSaveSuccess {
                                        Label("Saved!", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        Divider()
                        
                        // Rating and Color Tag
                        MetadataSectionView(title: "Rating & Color") {
                            VStack(alignment: .leading, spacing: 12) {
                                // Rating
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rating")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    RatingPicker(rating: $rating, onChange: { newRating in
                                        guard let photoId = photo.id else { return }
                                        photoLibrary.updatePhotoRating(photoId, rating: newRating)
                                    })
                                }
                                
                                // Color Tag
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Color Tag")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    ColorTagPicker(selectedColor: $colorTag, onChange: { newColor in
                                        guard let photoId = photo.id else { return }
                                        photoLibrary.updatePhotoColorTag(photoId, colorTag: newColor)
                                    })
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Basic info
                        MetadataSectionView(title: "File Information") {
                            MetadataRowView(label: "Filename", value: photo.fileName)
                            MetadataRowView(label: "Size", value: ByteCountFormatter().string(fromByteCount: photo.fileSize))
                            MetadataRowView(label: "Path", value: photo.relativePath)
                            
                            if let width = photo.imageWidth, let height = photo.imageHeight {
                                MetadataRowView(label: "Dimensions", value: "\(width) × \(height)")
                            }
                        }
                        
                        // Camera info
                        if hasExifData {
                            MetadataSectionView(title: "Camera Information") {
                                if let camera = photo.exifCameraModel {
                                    MetadataRowView(label: "Camera", value: camera)
                                }
                                
                                if let lens = photo.exifLensModel {
                                    MetadataRowView(label: "Lens", value: lens)
                                }
                            }
                        }
                        
                        // Exposure info
                        if hasExposureData {
                            MetadataSectionView(title: "Exposure") {
                                if let aperture = photo.exifAperture {
                                    MetadataRowView(label: "Aperture", value: "f/\(aperture)")
                                }
                                
                                if let shutterSpeed = photo.exifShutterSpeed {
                                    MetadataRowView(label: "Shutter Speed", value: shutterSpeed)
                                }
                                
                                if let iso = photo.exifIso {
                                    MetadataRowView(label: "ISO", value: "\(iso)")
                                }
                                
                                if let focalLength = photo.exifFocalLength {
                                    MetadataRowView(label: "Focal Length", value: "\(focalLength)mm")
                                }
                            }
                        }
                        
                        // Date info
                        MetadataSectionView(title: "Dates") {
                            if let dateTaken = photo.exifDateTaken {
                                MetadataRowView(label: "Date Taken", value: dateTaken.formatted(date: .abbreviated, time: .shortened))
                            }
                            
                            MetadataRowView(label: "Created", value: photo.createdAt.formatted(date: .abbreviated, time: .shortened))
                            MetadataRowView(label: "Modified", value: photo.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        
                        // Technical info
                        MetadataSectionView(title: "Technical") {
                            MetadataRowView(label: "File Hash", value: photo.fileHash)
                            MetadataRowView(label: "Has Thumbnail", value: photo.hasThumbnail ? "Yes" : "No")
                        }
                        
                        // Actions
                        MetadataSectionView(title: "Actions") {
                            Button(action: showInFinder) {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: openWithDefaultApp) {
                                Label("Open in Default App", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { showingOpenWithPicker = true }) {
                                Label("Open With...", systemImage: "ellipsis.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
            }
            .frame(width: 400)
        }
        .frame(minWidth: 1200, idealWidth: 1400, minHeight: 800, idealHeight: 900)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text(photo.fileName)
                    .font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadFullImage()
            // Always reload metadata from database when view appears
            currentPhotoId = nil // Force reload
            loadPhotoMetadata()
        }
        .onChange(of: photo.id) { oldValue, newValue in
            // Photo changed, reload metadata
            currentPhotoId = nil // Force reload
            loadPhotoMetadata()
        }
        .sheet(isPresented: $showingFullscreenImage) {
            FullscreenImageView(image: fullImage, fileName: photo.fileName)
        }
        .sheet(isPresented: $showingOpenWithPicker) {
            OpenWithPickerView(photoPath: getPhotoPath())
        }
    }
    
    private var hasExifData: Bool {
        photo.exifCameraModel != nil || photo.exifLensModel != nil
    }
    
    private var hasExposureData: Bool {
        photo.exifAperture != nil || photo.exifShutterSpeed != nil || 
        photo.exifIso != nil || photo.exifFocalLength != nil
    }
    
    private func loadPhotoMetadata() {
        guard let photoId = photo.id else { 
            print("❌ PhotoDetailView: No photo ID for metadata load")
            return 
        }
        
        print("🔍 PhotoDetailView: Loading metadata for photo ID: \(photoId)")
        
        // Always try to get fresh data from database
        if let freshPhoto = photoLibrary.getPhotoById(photoId) {
            userDescription = freshPhoto.userDescription ?? ""
            userTags = freshPhoto.userTags ?? ""
            rating = freshPhoto.rating
            colorTag = freshPhoto.colorTag
            currentPhotoId = photoId
            print("🔄 PhotoDetailView: Loaded fresh metadata from DB")
            print("   Description: \(freshPhoto.userDescription ?? "nil")")
            print("   Tags: \(freshPhoto.userTags ?? "nil")")
            print("   Rating: \(freshPhoto.rating)")
            print("   Color: \(freshPhoto.colorTag ?? "nil")")
        } else {
            // Fall back to original photo data
            userDescription = photo.userDescription ?? ""
            userTags = photo.userTags ?? ""
            rating = photo.rating
            colorTag = photo.colorTag
            currentPhotoId = photoId
            print("⚠️ PhotoDetailView: Using stale photo data (DB lookup failed)")
        }
    }
    
    private func saveMetadata() {
        guard let photoId = photo.id else {
            print("❌ PhotoDetailView: No photo ID available")
            return
        }
        
        let description = userDescription.isEmpty ? nil : userDescription
        let tags = userTags.isEmpty ? nil : userTags
        
        print("💾 PhotoDetailView: Saving metadata for photo ID: \(photoId)")
        print("   Description: \(description ?? "nil")")
        print("   Tags: \(tags ?? "nil")")
        
        photoLibrary.updatePhotoMetadata(photoId, description: description, tags: tags)
        hasUnsavedChanges = false
        showingSaveSuccess = true
        
        // Hide success message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingSaveSuccess = false
        }
        
        print("✅ PhotoDetailView: Metadata saved successfully")
    }
    
    private func getPhotoPath() -> String {
        guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            return photo.relativePath
        }
        return (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
    }
    
    private func showInFinder() {
        let fullPath = getPhotoPath()
        let fileURL = URL(fileURLWithPath: fullPath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    
    private func openWithDefaultApp() {
        guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
            print("❌ Cannot find root directory")
            return
        }
        
        // Try to restore security-scoped access if we have bookmark data
        var directoryURL: URL? = nil
        var isAccessingSecurityScope = false
        
        if let bookmarkData = rootDirectory.bookmarkData {
            do {
                var isStale = false
                directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: [.withSecurityScope],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)
                
                if let url = directoryURL {
                    isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                    print("🔓 Security-scoped access for open: \(isAccessingSecurityScope)")
                }
            } catch {
                print("⚠️ Failed to resolve bookmark: \(error.localizedDescription)")
            }
        }
        
        let fullPath = getPhotoPath()
        let fileURL = URL(fileURLWithPath: fullPath)
        NSWorkspace.shared.open(fileURL)
        
        // Don't stop accessing immediately - let the other app open the file
        if isAccessingSecurityScope {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                directoryURL?.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    private func loadFullImage() {
        Task {
            // Get the full path to the image
            guard let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) else {
                print("❌ PhotoDetailView: Cannot find root directory for photo")
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            let fullPath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
            print("📷 PhotoDetailView: Loading image from: \(fullPath)")
            
            // Check if file exists
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: fullPath) {
                print("❌ PhotoDetailView: File does not exist at path")
                await MainActor.run {
                    fullImage = photoLibrary.getThumbnailImage(for: photo)
                    isLoading = false
                }
                return
            }
            
            // Try to restore security-scoped access if we have bookmark data
            var directoryURL: URL? = nil
            var isAccessingSecurityScope = false
            
            if let bookmarkData = rootDirectory.bookmarkData {
                do {
                    var isStale = false
                    directoryURL = try URL(resolvingBookmarkData: bookmarkData,
                                          options: [.withSecurityScope],
                                          relativeTo: nil,
                                          bookmarkDataIsStale: &isStale)
                    
                    if let url = directoryURL {
                        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                        print("🔓 PhotoDetailView: Security-scoped access: \(isAccessingSecurityScope)")
                    }
                } catch {
                    print("⚠️ PhotoDetailView: Failed to resolve bookmark: \(error.localizedDescription)")
                }
            }
            
            defer {
                if isAccessingSecurityScope, let url = directoryURL {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            await MainActor.run {
                if let image = NSImage(contentsOfFile: fullPath) {
                    fullImage = image
                    print("✅ PhotoDetailView: Loaded full image - Size: \(image.size.width)x\(image.size.height)")
                } else {
                    print("⚠️ PhotoDetailView: NSImage failed to load, trying thumbnail")
                    // Try loading thumbnail as fallback
                    fullImage = photoLibrary.getThumbnailImage(for: photo)
                    if let thumb = fullImage {
                        print("📸 PhotoDetailView: Loaded thumbnail - Size: \(thumb.size.width)x\(thumb.size.height)")
                    }
                }
                isLoading = false
            }
        }
    }
}

// MARK: - Rating Picker Component
struct RatingPicker: View {
    @Binding var rating: Int
    let onChange: (Int) -> Void
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(0..<6) { index in
                Button {
                    let newRating = rating == index ? 0 : index
                    rating = newRating
                    onChange(newRating)
                } label: {
                    Image(systemName: index <= rating ? "flag.fill" : "flag")
                        .foregroundColor(index <= rating ? .orange : .gray.opacity(0.4))
                        .font(isCompact ? .caption : .body)
                }
                .buttonStyle(.plain)
                .help("\(index) flag\(index == 1 ? "" : "s")")
            }
        }
    }
}

// MARK: - Color Tag Picker Component
struct ColorTagPicker: View {
    @Binding var selectedColor: String?
    let onChange: (String?) -> Void
    var isCompact: Bool = false
    
    private let colorOptions: [(id: String, color: Color)] = [
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("blue", .blue),
        ("purple", .purple),
        ("gray", .gray)
    ]
    
    var body: some View {
        HStack(spacing: isCompact ? 4 : 8) {
            // Clear button
            Button {
                selectedColor = nil
                onChange(nil)
            } label: {
                Image(systemName: selectedColor == nil ? "circle.fill" : "circle")
                    .foregroundColor(selectedColor == nil ? .primary : .gray.opacity(0.3))
                    .font(isCompact ? .caption : .body)
            }
            .buttonStyle(.plain)
            .help("No color")
            
            ForEach(colorOptions, id: \.id) { option in
                Button {
                    let newColor = selectedColor == option.id ? nil : option.id
                    selectedColor = newColor
                    onChange(newColor)
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: isCompact ? 12 : 16, height: isCompact ? 12 : 16)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            selectedColor == option.id ?
                            Image(systemName: "checkmark")
                                .font(.system(size: isCompact ? 8 : 10, weight: .bold))
                                .foregroundColor(.white)
                            : nil
                        )
                }
                .buttonStyle(.plain)
                .help(option.id.capitalized)
            }
        }
    }
}

struct MetadataSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            content
        }
    }
}

struct MetadataRowView: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

struct FullscreenImageView: View {
    let image: NSImage?
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: max(geometry.size.width, image.size.width) * zoomScale,
                                height: max(geometry.size.height, image.size.height) * zoomScale
                            )
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = zoomScale
                            }
                    )
                } else {
                    Text("Image not available")
                        .foregroundColor(.white)
                }
                
                // Top overlay with close button and filename
                VStack {
                    HStack {
                        Text(fileName)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                        
                        Spacer()
                        
                        Text("Press Control+Cmd+F for fullscreen")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.trailing)
                        
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding()
                    }
                    .background(.black.opacity(0.5))
                
                Spacer()
                
                // Zoom controls
                HStack(spacing: 20) {
                    Button {
                        withAnimation {
                            zoomScale = max(0.5, zoomScale - 0.25)
                            lastScale = zoomScale
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation {
                            zoomScale = 1.0
                            lastScale = 1.0
                        }
                    } label: {
                        Text("\(Int(zoomScale * 100))%")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation {
                            zoomScale = min(5.0, zoomScale + 0.25)
                            lastScale = zoomScale
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.bottom, 20)
                }
            }
        }
        .frame(minWidth: 1200, idealWidth: 1600, maxWidth: .infinity,
               minHeight: 900, idealHeight: 1200, maxHeight: .infinity)
        .onAppear {
            // Try to maximize the window on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApplication.shared.windows.last {
                    // Get screen size
                    if let screen = window.screen {
                        let screenFrame = screen.visibleFrame
                        // Set window to 90% of screen size
                        let newFrame = NSRect(
                            x: screenFrame.origin.x + screenFrame.width * 0.05,
                            y: screenFrame.origin.y + screenFrame.height * 0.05,
                            width: screenFrame.width * 0.9,
                            height: screenFrame.height * 0.9
                        )
                        window.setFrame(newFrame, display: true, animate: true)
                    }
                }
            }
        }
    }
}
