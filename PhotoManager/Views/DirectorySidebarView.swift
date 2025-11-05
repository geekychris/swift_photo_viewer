import SwiftUI
//foo
struct DirectorySidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedDirectoryId: Int64?
    @State private var expandedDirectories: Set<Int64> = []
    
    var body: some View {
        List(selection: $selectedDirectoryId) {
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
                .tag(directory.id ?? -1)
            }
        }
        .listStyle(SidebarListStyle())
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
                
                Button {
                    print("🔄 DirectoryRowView: Scan button clicked for directory: \(directory.name)")
                    onScan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Rescan directory")
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
        .onAppear {
            loadPhotos()
        }
        .onChange(of: photoLibrary.rootDirectories) {
            loadPhotos()
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
