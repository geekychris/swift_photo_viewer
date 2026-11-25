import SwiftUI
import os.log

private let sidebarLogger = Logger(subsystem: "com.photomarger", category: "sidebar")

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
        guard let id = directory.id else { return }
        if expandedDirectories.contains(id) {
            expandedDirectories.remove(id)
        } else {
            expandedDirectories.insert(id)
        }
    }
}


/// Folder hierarchy of one root built from per-directory photo counts.
/// Paths are relative to the root; "" is the root itself.
struct FolderTree {
    private(set) var direct: [String: Int] = [:]
    private(set) var total: [String: Int] = [:]
    private(set) var children: [String: [String]] = [:]

    init(counts: [(path: String, count: Int)] = []) {
        var kids: [String: Set<String>] = [:]
        for (path, count) in counts {
            direct[path, default: 0] += count
            var current = path
            total[current, default: 0] += count
            while !current.isEmpty {
                let parent = (current as NSString).deletingLastPathComponent
                kids[parent, default: []].insert(current)
                current = parent
                total[current, default: 0] += count
            }
        }
        children = kids.mapValues { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }

    var totalCount: Int { total[""] ?? 0 }
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
    @State private var tree = FolderTree()
    @State private var fileTypeStats: [(ext: String, count: Int)] = []
    @State private var expandedFolders: Set<String> = []
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
                    HStack {
                        Text(directory.name)
                            .fontWeight(.medium)
                        
                        Text("\(tree.totalCount) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                    
                    // File type breakdown
                    if !fileTypeStats.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(fileTypeStats, id: \.ext) { stat in
                                HStack(spacing: 2) {
                                    Text(stat.ext)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(stat.count)")
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
                        Task {
                            await photoLibrary.scanDirectory(directory, fastScan: true, regenerateThumbnails: false)
                        }
                    } label: {
                        Label("Fast Scan", systemImage: "bolt.fill")
                    }
                    
                    Button {
                        Task {
                            await photoLibrary.scanDirectory(directory, fastScan: false, regenerateThumbnails: false)
                        }
                    } label: {
                        Label("Full Scan", systemImage: "arrow.clockwise")
                    }
                    
                    Button {
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
                    // Files directly in the root, kept apart from real folders (one may be called "Root").
                    if (tree.direct[""] ?? 0) > 0 {
                        FolderNodeView(
                            rootId: directory.id,
                            path: "",
                            tree: tree,
                            expandedFolders: $expandedFolders,
                            selectedDirectoryId: $selectedDirectoryId,
                            selectedSubdirectoryPath: $selectedSubdirectoryPath,
                            selectedPhoto: $selectedPhoto
                        )
                    }
                    ForEach(tree.children[""] ?? [], id: \.self) { folder in
                        FolderNodeView(
                            rootId: directory.id,
                            path: folder,
                            tree: tree,
                            expandedFolders: $expandedFolders,
                            selectedDirectoryId: $selectedDirectoryId,
                            selectedSubdirectoryPath: $selectedSubdirectoryPath,
                            selectedPhoto: $selectedPhoto
                        )
                    }
                }
                .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .task(id: "\(directory.id ?? -1)-\(photoLibrary.libraryVersion)") {
            await loadCounts()
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
    
    private func loadCounts() async {
        guard let rootId = directory.id else { return }
        let db = photoLibrary.databaseManager
        let (counts, exts) = await Task.detached(priority: .userInitiated) { () -> ([(path: String, count: Int)], [(ext: String, count: Int)]) in
            do {
                return (try db.directoryCounts(rootId: rootId), try db.extensionCounts(rootId: rootId))
            } catch {
                sidebarLogger.error("Folder counts failed: \(error.localizedDescription, privacy: .public)")
                return ([], [])
            }
        }.value
        guard !Task.isCancelled else { return }
        tree = FolderTree(counts: counts)
        fileTypeStats = exts
            .map { (ext: $0.ext.isEmpty ? "Unknown" : $0.ext.uppercased(), count: $0.count) }
            .sorted { $0.ext < $1.ext }
    }
}

/// One folder in the tree: select it to show it (with subfolders) in the grid, expand it for
/// its subfolders and a preview of the files directly in it.
struct FolderNodeView: View {
    let rootId: Int64?
    let path: String
    let tree: FolderTree
    @Binding var expandedFolders: Set<String>
    @Binding var selectedDirectoryId: Int64?
    @Binding var selectedSubdirectoryPath: String?
    @Binding var selectedPhoto: PhotoFile?

    private var isRootFiles: Bool { path.isEmpty }
    private var isExpanded: Bool { expandedFolders.contains(path) }
    private var isSelected: Bool { selectedDirectoryId == rootId && selectedSubdirectoryPath == path }
    private var subfolders: [String] { isRootFiles ? [] : (tree.children[path] ?? []) }
    private var count: Int { isRootFiles ? (tree.direct[""] ?? 0) : (tree.total[path] ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    if isExpanded { expandedFolders.remove(path) } else { expandedFolders.insert(path) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: isRootFiles ? "doc.on.doc" : "folder.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    selectedDirectoryId = rootId
                    selectedSubdirectoryPath = path
                } label: {
                    HStack {
                        if isRootFiles {
                            Text("Files in top folder")
                                .font(.caption)
                                .italic()
                                .foregroundColor(.primary)
                        } else {
                            Text((path as NSString).lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(subfolders, id: \.self) { child in
                        FolderNodeView(
                            rootId: rootId,
                            path: child,
                            tree: tree,
                            expandedFolders: $expandedFolders,
                            selectedDirectoryId: $selectedDirectoryId,
                            selectedSubdirectoryPath: $selectedSubdirectoryPath,
                            selectedPhoto: $selectedPhoto
                        )
                    }
                    if (tree.direct[path] ?? 0) > 0 {
                        FolderPreviewView(rootId: rootId, path: path, directCount: tree.direct[path] ?? 0, selectedPhoto: $selectedPhoto)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

/// Up to 20 thumbnails of the files directly in a folder, loaded on demand.
struct FolderPreviewView: View {
    let rootId: Int64?
    let path: String
    let directCount: Int
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var photos: [PhotoFile] = []

    private static let limit = 20

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 60), spacing: 4)], spacing: 4) {
            ForEach(photos) { photo in
                ReusableHoverThumbnail(photo: photo, size: 50, onTap: {
                    selectedPhoto = photo
                })
                .environmentObject(photoLibrary)
            }

            if directCount > Self.limit {
                VStack {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                    Text("+\(directCount - Self.limit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(.top, 4)
        .task(id: "\(rootId ?? -1)/\(path)/\(photoLibrary.libraryVersion)") {
            guard let rootId else { return }
            var filter = PhotoFilter()
            filter.rootDirectoryId = rootId
            filter.directoryPath = path
            let db = photoLibrary.databaseManager
            let loaded = await Task.detached(priority: .utility) {
                (try? db.photos(matching: filter, sort: .name, limit: Self.limit)) ?? []
            }.value
            guard !Task.isCancelled else { return }
            photos = loaded
        }
    }
}
