import SwiftUI

/// Shared formatter for the duplicate screens (creating one per row is costly).
enum DuplicateFormat {
    static let bytes = ByteCountFormatter()
    static func size(_ bytes: Int64) -> String { Self.bytes.string(fromByteCount: bytes) }
}

struct SimplifiedDuplicatesView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var selectedFilesForDeletion: Set<Int64> = []
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeletion: [PhotoFile] = []
    @State private var trashResultMessage: String?
    @State private var expandedGroups: Set<String> = []
    @State private var searchText = ""

    // Cached, recomputed only when the duplicate groups, roots or (debounced) search text change.
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var totalDuplicateFiles = 0
    @State private var totalWastedSpace: Int64 = 0
    @State private var sourceVersion = 0
    @State private var appliedSearch = ""

    private var selectedFiles: [PhotoFile] {
        duplicateGroups.flatMap { $0.files }.filter { file in
            file.id.map { selectedFilesForDeletion.contains($0) } ?? false
        }
    }

    /// Filters and sorts the groups off the main thread.
    private func recompute() async {
        if searchText != appliedSearch {
            try? await Task.sleep(nanoseconds: 300_000_000)  // debounce typing
            if Task.isCancelled { return }
        }
        let search = searchText
        let source = photoLibrary.duplicateGroups
        let rootPaths = Dictionary(photoLibrary.rootDirectories.compactMap { r in r.id.map { ($0, r.path) } },
                                   uniquingKeysWith: { a, _ in a })
        let groups = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            var result: [DuplicateGroup] = []
            for group in source where group.files.count > 1 {
                if Task.isCancelled { return [] }
                // Drop files whose library root is gone; keep the group only if it is still a duplicate.
                let validFiles = group.files.filter { rootPaths[$0.rootDirectoryId] != nil }
                guard validFiles.count > 1 else { continue }
                if !search.isEmpty {
                    let matches = validFiles.contains { file in
                        file.fileName.localizedCaseInsensitiveContains(search) ||
                        ((rootPaths[file.rootDirectoryId]! as NSString).appendingPathComponent(file.relativePath))
                            .localizedCaseInsensitiveContains(search)
                    }
                    guard matches else { continue }
                }
                let totalSize = validFiles.reduce(0) { $0 + $1.fileSize }
                result.append(DuplicateGroup(fileHash: group.fileHash, files: validFiles, totalSize: totalSize))
            }
            return result.sorted { $0.files.count > $1.files.count }
        }.value
        if Task.isCancelled { return }
        duplicateGroups = groups
        appliedSearch = search
        totalDuplicateFiles = groups.reduce(0) { $0 + ($1.files.count - 1) }
        totalWastedSpace = groups.reduce(0) { total, group in
            total + (group.files.first?.fileSize ?? 0) * Int64(group.files.count - 1)
        }
        // Forget selections of files that are gone (e.g. trashed).
        let visibleIds = Set(groups.flatMap { $0.files.compactMap(\.id) })
        if search.isEmpty { selectedFilesForDeletion.formIntersection(visibleIds) }
    }

    private func trash(_ files: [PhotoFile]) {
        guard !files.isEmpty else { return }
        let result = photoLibrary.trashPhotos(files)  // one guarded call; it refreshes the duplicate lists
        selectedFilesForDeletion.subtract(files.compactMap(\.id))
        trashResultMessage = result.summary + "."
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
                            
                            Label(DuplicateFormat.size(totalWastedSpace) + " wasted", systemImage: "externaldrive.badge.exclamationmark")
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
                                pendingDeletion = selectedFiles
                                showingDeleteConfirmation = !pendingDeletion.isEmpty
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
                                onTrash: { file in trash([file]) },
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
        .overlay {
            if photoLibrary.isLoadingDuplicates && duplicateGroups.isEmpty {
                ProgressView("Finding duplicates…")
            }
        }
        .task(id: "\(sourceVersion)|\(searchText)") { await recompute() }
        .onReceive(photoLibrary.$duplicateGroups.dropFirst()) { _ in sourceVersion += 1 }
        .onReceive(photoLibrary.$rootDirectories.dropFirst()) { _ in sourceVersion += 1 }
        .alert("Delete \(pendingDeletion.count) Files", isPresented: $showingDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) {
                trash(pendingDeletion)
                pendingDeletion = []
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            let totalSize = pendingDeletion.reduce(0) { $0 + $1.fileSize }
            Text("Move \(pendingDeletion.count) files (\(DuplicateFormat.size(totalSize))) to the Trash?\n\nOne copy of every photo is always kept. You can restore files from the Trash if needed.")
        }
        .alert("Duplicates", isPresented: Binding(get: { trashResultMessage != nil }, set: { if !$0 { trashResultMessage = nil } })) {
            Button("OK", role: .cancel) { trashResultMessage = nil }
        } message: {
            Text(trashResultMessage ?? "")
        }
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    @Binding var selectedFiles: Set<Int64>
    @Binding var selectedPhoto: PhotoFile?
    let onTrash: (PhotoFile) -> Void
    let onToggle: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingKeepHint = false
    
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
    
    private var selectedCount: Int {
        group.files.filter { $0.id.map { selectedFiles.contains($0) } ?? false }.count
    }

    /// Every copy but one is selected; one copy of a group is always kept.
    private var allSelected: Bool {
        group.files.count > 1 && selectedCount >= group.files.count - 1
    }

    private func flashKeepHint() {
        showingKeepHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showingKeepHint = false }
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
                            Text(DuplicateFormat.size(fileSize) + " each")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(DuplicateFormat.size(wastedSpace) + " wasted")
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
                            // Select every copy but one: keep an already-unselected copy, else the first
                            let keep = group.files.first { !($0.id.map { selectedFiles.contains($0) } ?? false) } ?? group.files[0]
                            for file in group.files where file.id != keep.id {
                                if let id = file.id {
                                    selectedFiles.insert(id)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: allSelected ? "checkmark.square.fill" : "square.dashed")
                                .foregroundColor(allSelected ? .blue : .gray)
                            Text("Select All but One")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Selects every copy except one; one copy is always kept")
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
                    if showingKeepHint {
                        Label("One copy is always kept", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.leading, 12)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(group.files) { file in
                        DuplicateFileRow(
                            file: file,
                            isSelected: selectedFiles.contains(file.id ?? 0),
                            canTrash: group.files.count > 1,
                            selectedPhoto: $selectedPhoto,
                            onToggleSelection: {
                                if let id = file.id {
                                    if selectedFiles.contains(id) {
                                        selectedFiles.remove(id)
                                    } else if selectedCount >= group.files.count - 1 {
                                        flashKeepHint()  // would select the last unselected copy
                                    } else {
                                        selectedFiles.insert(id)
                                    }
                                }
                            },
                            onTrash: { onTrash(file) }
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
    /// False when this is the only remaining copy.
    let canTrash: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggleSelection: () -> Void
    let onTrash: () -> Void
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
                    
                    Text(DuplicateFormat.size(file.fileSize))
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
                        .foregroundColor(canTrash ? .red : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!canTrash)
                .help(canTrash ? "Move to trash" : "This is the only copy")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .alert("Move to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                onTrash()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Move '\(file.fileName)' to the Trash?\n\nLocation: \(fullPath)")
        }
    }
}
