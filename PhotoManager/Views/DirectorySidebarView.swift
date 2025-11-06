import SwiftUI
//foo
struct DirectorySidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedDirectoryId: Int64?
    @Binding var selectedSubdirectoryPath: String?
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var expandedDirectories: Set<Int64> = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                        ForEach(photoLibrary.rootDirectories) { directory in
                    DirectoryRowView(
                        directory: directory,
                        isExpanded: expandedDirectories.contains(directory.id ?? -1),
                        selectedDirectoryId: $selectedDirectoryId,
                        selectedSubdirectoryPath: $selectedSubdirectoryPath,
                        selectedPhoto: $selectedPhoto,
                        onToggleExpanded: {
                            toggleExpansion(for: directory)
                        },
                        onScan: {
                            Task {
                                await photoLibrary.scanDirectory(directory)
                            }
                        }
                    )
                    .background(selectedDirectoryId == directory.id && selectedSubdirectoryPath == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedDirectoryId = directory.id
                        selectedSubdirectoryPath = nil // Select root directory
                    }
                    
                        Divider()
                    }
                }
                .frame(width: sidebarWidth - 20)
                .padding(.horizontal, 10)
        }
    }
    }
    
    private func toggleExpansion(for directory: RootDirectory) {
        guard let id = directory.id else { 
            print("⚠️ DirectorySidebarView: Directory has no ID for toggle")
            return 
        }
        
        if expandedDirectories.contains(id) {
            print("🔽 DirectorySidebarView: Collapsing directory: \(directory.name)")
            expandedDirectories.remove(id)
        } else {
            print("🔼 DirectorySidebarView: Expanding directory: \(directory.name)")
            expandedDirectories.insert(id)
        }
    }
}

struct DirectoryRowView: View {
    let directory: RootDirectory
    let isExpanded: Bool
    @Binding var selectedDirectoryId: Int64?
    @Binding var selectedSubdirectoryPath: String?
    @Binding var selectedPhoto: PhotoFile?
    let onToggleExpanded: () -> Void
    let onScan: () -> Void
    
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var photos: [PhotoFile] = []
    @State private var subdirectories: [String: [PhotoFile]] = [:]
    @State private var expandedSubdirectories: Set<String> = []
    @State private var showingScanOptions = false
    @State private var showingDeleteAlert = false
    
    private var fileTypeStats: [String: Int] {
        let grouped = Dictionary(grouping: photos) { photo -> String in
            let ext = (photo.fileName as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "Unknown" : ext
        }
        return grouped.mapValues { $0.count }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Button {
                    onToggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(directory.name)
                            .fontWeight(.medium)
                        
                        Text("\(photos.count) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                    
                    // File type breakdown
                    if !fileTypeStats.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(fileTypeStats.keys.sorted()), id: \.self) { ext in
                                HStack(spacing: 2) {
                                    Text(ext)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(fileTypeStats[ext] ?? 0)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(3)
                            }
                        }
                    }
                    
                    Text(directory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let lastScanned = directory.lastScannedAt {
                        Text("Last scanned: \(lastScanned, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Spacer()
                
                Menu {
                    Button {
                        print("🔄 DirectoryRowView: Fast scan clicked for directory: \(directory.name)")
                        Task {
                            await photoLibrary.scanDirectory(directory, fastScan: true, regenerateThumbnails: false)
                        }
                    } label: {
                        Label("Fast Scan", systemImage: "bolt.fill")
                    }
                    
                    Button {
                        print("🔄 DirectoryRowView: Full scan clicked for directory: \(directory.name)")
                        Task {
                            await photoLibrary.scanDirectory(directory, fastScan: false, regenerateThumbnails: false)
                        }
                    } label: {
                        Label("Full Scan", systemImage: "arrow.clockwise")
                    }
                    
                    Button {
                        print("🖼 DirectoryRowView: Regenerate all thumbnails clicked for directory: \(directory.name)")
                        Task {
                            await photoLibrary.scanDirectory(directory, fastScan: false, regenerateThumbnails: true)
                        }
                    } label: {
                        Label("Full Scan + Regenerate Thumbnails", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Remove Directory", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Directory options")
                .menuStyle(BorderlessButtonMenuStyle())
            }
            
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(subdirectories.keys.sorted(), id: \.self) { subdirectory in
                        SubdirectoryRowView(
                            subdirectory: subdirectory,
                            photos: subdirectories[subdirectory] ?? [],
                            isExpanded: expandedSubdirectories.contains(subdirectory),
                            isSelected: selectedDirectoryId == directory.id && selectedSubdirectoryPath == subdirectory,
                            selectedPhoto: $selectedPhoto,
                            onToggle: {
                                if expandedSubdirectories.contains(subdirectory) {
                                    expandedSubdirectories.remove(subdirectory)
                                } else {
                                    expandedSubdirectories.insert(subdirectory)
                                }
                            },
                            onSelect: {
                                selectedDirectoryId = directory.id
                                selectedSubdirectoryPath = subdirectory
                            }
                        )
                    }
                }
                .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            loadPhotos()
        }
        .onChange(of: photoLibrary.rootDirectories) {
            loadPhotos()
        }
        .alert("Remove Directory", isPresented: $showingDeleteAlert) {
            Button("Remove", role: .destructive) {
                photoLibrary.deleteRootDirectory(directory)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove \"\(directory.name)\" from the app and delete all associated data. Your actual photo files will not be affected. This action cannot be undone.")
        }
    }
    
    private func loadPhotos() {
        guard let directoryId = directory.id else { 
            print("⚠️ DirectoryRowView: Directory has no ID for loading photos")
            return 
        }
        
        print("📷 DirectoryRowView: Loading photos for directory: \(directory.name) (ID: \(directoryId))")
        photos = photoLibrary.getPhotosForDirectory(directoryId)
        print("📊 DirectoryRowView: Loaded \(photos.count) photos for \(directory.name)")
        
        // Group photos by subdirectory
        subdirectories = Dictionary(grouping: photos) { photo in
            let pathComponents = photo.relativePath.split(separator: "/")
            if pathComponents.count > 1 {
                return String(pathComponents[0])
            } else {
                return "Root"
            }
        }
        print("🗺 DirectoryRowView: Grouped into \(subdirectories.count) subdirectories")
    }
}

struct SubdirectoryRowView: View {
    let subdirectory: String
    let photos: [PhotoFile]
    let isExpanded: Bool
    let isSelected: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggle: () -> Void
    let onSelect: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onSelect) {
                    HStack {
                        Text(subdirectory)
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(photos.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            
            if isExpanded {
                // Show thumbnails in a grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 60), spacing: 4)], spacing: 4) {
                    ForEach(photos.prefix(20)) { photo in
                        ReusableHoverThumbnail(photo: photo, size: 50, onTap: {
                            selectedPhoto = photo
                        })
                        .environmentObject(photoLibrary)
                    }
                    
                    if photos.count > 20 {
                        VStack {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.secondary)
                            Text("+\(photos.count - 20)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
    }
}
