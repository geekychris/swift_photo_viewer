import SwiftUI
//foo
struct DirectorySidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedDirectoryId: Int64?
    @Binding var sidebarWidth: CGFloat
    @State private var expandedDirectories: Set<Int64> = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                        ForEach(photoLibrary.rootDirectories) { directory in
                    DirectoryRowView(
                        directory: directory,
                        isExpanded: expandedDirectories.contains(directory.id ?? -1),
                        onToggleExpanded: {
                            toggleExpansion(for: directory)
                        },
                        onScan: {
                            Task {
                                await photoLibrary.scanDirectory(directory)
                            }
                        }
                    )
                    .background(selectedDirectoryId == directory.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedDirectoryId = directory.id
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
    let onToggleExpanded: () -> Void
    let onScan: () -> Void
    
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var photos: [PhotoFile] = []
    @State private var subdirectories: [String: [PhotoFile]] = [:]
    @State private var showingScanOptions = false
    @State private var showingDeleteAlert = false
    
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
                    Text(directory.name)
                        .fontWeight(.medium)
                    
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(subdirectories.keys.sorted(), id: \.self) { subdirectory in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text(subdirectory)
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(subdirectories[subdirectory]?.count ?? 0)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
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
