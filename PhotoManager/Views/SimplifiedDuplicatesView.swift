import SwiftUI

struct SimplifiedDuplicatesView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var selectedFilesForDeletion: Set<Int64> = []
    @State private var showingDeleteConfirmation = false
    @State private var expandedGroups: Set<String> = []
    @State private var searchText = ""
    @State private var refreshTrigger = 0  // Force view refresh
    
    private var duplicateGroups: [DuplicateGroup] {
        let groups = photoLibrary.duplicateGroups
            .filter { $0.files.count > 1 }
            // Filter out groups where files have missing root directories
            .compactMap { group -> DuplicateGroup? in
                // Check if all files have valid root directories
                let validFiles = group.files.filter { file in
                    photoLibrary.rootDirectories.contains(where: { $0.id == file.rootDirectoryId })
                }
                
                // Only include group if at least 2 files have valid roots (still duplicates)
                if validFiles.count > 1 {
                    let totalSize = validFiles.reduce(0) { $0 + $1.fileSize }
                    return DuplicateGroup(fileHash: group.fileHash, files: validFiles, totalSize: totalSize)
                } else {
                    if group.files.count != validFiles.count {
                        print("⚠️ Filtered out \(group.files.count - validFiles.count) files with missing root directories from hash \(String(group.fileHash.prefix(8)))")
                    }
                    return nil
                }
            }
            .sorted { $0.files.count > $1.files.count }
        
        if searchText.isEmpty {
            return groups
        } else {
            return groups.filter { group in
                group.files.contains { file in
                    file.fileName.localizedCaseInsensitiveContains(searchText) ||
                    getFullPath(for: file).localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    private var totalDuplicateFiles: Int {
        duplicateGroups.reduce(0) { $0 + ($1.files.count - 1) }
    }
    
    private var totalWastedSpace: Int64 {
        duplicateGroups.reduce(0) { total, group in
            let fileSize = group.files.first?.fileSize ?? 0
            return total + (fileSize * Int64(group.files.count - 1))
        }
    }
    
    private var selectedFiles: [PhotoFile] {
        photoLibrary.duplicateGroups
            .flatMap { $0.files }
            .filter { file in
                if let id = file.id {
                    return selectedFilesForDeletion.contains(id)
                }
                return false
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(duplicateGroups.count) Duplicate Groups")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Label("\(totalDuplicateFiles) duplicate files", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label(ByteCountFormatter().string(fromByteCount: totalWastedSpace) + " wasted", systemImage: "externaldrive.badge.exclamationmark")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    if !selectedFilesForDeletion.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(selectedFilesForDeletion.count) selected")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Button {
                                selectedFilesForDeletion.removeAll()
                            } label: {
                                Text("Clear")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                showingDeleteConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                    Text("Delete Selected")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search duplicates...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Duplicate groups list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if duplicateGroups.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            
                            Text(searchText.isEmpty ? "No Duplicates Found" : "No Matching Duplicates")
                                .font(.headline)
                            
                            Text(searchText.isEmpty ? "All files are unique." : "Try a different search term.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        ForEach(duplicateGroups, id: \.fileHash) { group in
                            DuplicateGroupRow(
                                group: group,
                                isExpanded: expandedGroups.contains(group.fileHash),
                                selectedFiles: $selectedFilesForDeletion,
                                selectedPhoto: $selectedPhoto,
                                onToggle: {
                                    if expandedGroups.contains(group.fileHash) {
                                        expandedGroups.remove(group.fileHash)
                                    } else {
                                        expandedGroups.insert(group.fileHash)
                                    }
                                }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle("All Duplicates")
        .alert("Delete \(selectedFiles.count) Files", isPresented: $showingDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) {
                let filesToDelete = selectedFiles  // Capture files
                selectedFilesForDeletion.removeAll()
                
                // Delete files asynchronously to avoid blocking UI
                Task {
                    print("🗑️ Starting batch deletion of \(filesToDelete.count) files")
                    for file in filesToDelete {
                        photoLibrary.movePhotoToTrash(file)
                    }
                    
                    // Refresh duplicates ONCE after all deletions
                    print("🔄 Refreshing duplicate groups after batch deletion")
                    await MainActor.run {
                        photoLibrary.loadDuplicates()
                        // Trigger UI refresh
                        refreshTrigger += 1
                    }
                    print("✅ Deletion and refresh complete")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let totalSize = selectedFiles.reduce(0) { $0 + $1.fileSize }
            Text("Move \(selectedFiles.count) files (\(ByteCountFormatter().string(fromByteCount: totalSize))) to the Trash?\n\nYou can restore them from Trash if needed.")
        }
    }
    
    private func getFullPath(for photo: PhotoFile) -> String {
        if let absolutePath = photo.getAbsoluteFullPath(rootDirectories: photoLibrary.rootDirectories) {
            return absolutePath
        }
        // Return empty string if path can't be determined
        return ""
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    @Binding var selectedFiles: Set<Int64>
    @Binding var selectedPhoto: PhotoFile?
    let onToggle: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    private var fileSize: Int64 {
        group.files.first?.fileSize ?? 0
    }
    
    private var wastedSpace: Int64 {
        fileSize * Int64(group.files.count - 1)
    }
    
    private var isSameDirectory: Bool {
        let directories = Set(group.files.map { getDirectoryPath(for: $0) })
        return directories.count == 1
    }
    
    private var uniqueDirectories: Set<String> {
        Set(group.files.map { getDirectoryPath(for: $0) })
    }
    
    private var allSelected: Bool {
        group.files.allSatisfy { file in
            if let id = file.id {
                return selectedFiles.contains(id)
            }
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                onToggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // Thumbnail of first file
                    ReusableHoverThumbnail(photo: group.files[0], size: 50, onTap: {
                        selectedPhoto = group.files[0]
                    })
                    .frame(width: 50, height: 50)
                    .environmentObject(photoLibrary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(group.files.count) copies")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            if isSameDirectory {
                                Label("Same directory", systemImage: "folder.fill")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            } else {
                                Label("\(uniqueDirectories.count) directories", systemImage: "folder.fill.badge.gearshape")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Text(ByteCountFormatter().string(fromByteCount: fileSize) + " each")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(ByteCountFormatter().string(fromByteCount: wastedSpace) + " wasted")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(group.fileHash.prefix(12)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Select all button for this group
                    Button {
                        if allSelected {
                            // Deselect all
                            for file in group.files {
                                if let id = file.id {
                                    selectedFiles.remove(id)
                                }
                            }
                        } else {
                            // Select all
                            for file in group.files {
                                if let id = file.id {
                                    selectedFiles.insert(id)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: allSelected ? "checkmark.square.fill" : "square.dashed")
                                .foregroundColor(allSelected ? .blue : .gray)
                            Text("Select All")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.05))
            
            // Expanded file list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.files) { file in
                        DuplicateFileRow(
                            file: file,
                            isSelected: selectedFiles.contains(file.id ?? 0),
                            selectedPhoto: $selectedPhoto,
                            onToggleSelection: {
                                if let id = file.id {
                                    if selectedFiles.contains(id) {
                                        selectedFiles.remove(id)
                                    } else {
                                        selectedFiles.insert(id)
                                    }
                                }
                            }
                        )
                        .environmentObject(photoLibrary)
                        
                        if file.id != group.files.last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.leading, 30)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.02))
            }
        }
    }
    
    private func getDirectoryPath(for photo: PhotoFile) -> String {
        return photo.getAbsoluteDirectoryPath(rootDirectories: photoLibrary.rootDirectories) ?? ""
    }
}

struct DuplicateFileRow: View {
    let file: PhotoFile
    let isSelected: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggleSelection: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    
    private var fullPath: String {
        return file.getAbsoluteFullPath(rootDirectories: photoLibrary.rootDirectories) ?? "[ERROR: Missing root directory]"
    }
    
    private var directoryPath: String {
        (fullPath as NSString).deletingLastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                onToggleSelection()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .buttonStyle(.plain)
            
            // Thumbnail with hover
            ReusableHoverThumbnail(photo: file, size: 50, onTap: {
                selectedPhoto = file
            })
            .frame(width: 50, height: 50)
            .environmentObject(photoLibrary)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                // Show full path including filename
                Text(fullPath)
                    .font(.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
                
                HStack(spacing: 8) {
                    if let dateTaken = file.exifDateTaken {
                        Text(dateTaken, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if file.exifDateTaken != nil {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: directoryPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                
                Button {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Move to trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .alert("Move to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                photoLibrary.movePhotoToTrash(file)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Move '\(file.fileName)' to the Trash?\n\nLocation: \(fullPath)")
        }
    }
}
