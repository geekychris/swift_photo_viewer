import SwiftUI

struct DuplicatesByDirectoryView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var expandedDirectories: Set<String> = []
    @State private var expandedCompleteDuplicates: Set<String> = []
    
    var body: some View {
        ScrollView {
                LazyVStack(spacing: 0) {
                if photoLibrary.directoryDuplicates.isEmpty && photoLibrary.completeDuplicateDirectories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("No Directory Duplicates Found")
                            .font(.headline)
                        
                        Text("No directories contain duplicate files.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    // Complete duplicate directories section
                    if !photoLibrary.completeDuplicateDirectories.isEmpty {
                        Text("Complete Duplicate Directories")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        ForEach(photoLibrary.completeDuplicateDirectories, id: \.primaryDirectory) { completeDir in
                            CompleteDuplicateDirectoryRowView(
                                completeDir: completeDir,
                                isExpanded: expandedCompleteDuplicates.contains(completeDir.primaryDirectory.fullPath),
                                selectedPhoto: $selectedPhoto,
                                onToggleExpanded: {
                                    toggleCompleteDuplicateExpansion(for: completeDir)
                                }
                            )
                            
                            Divider()
                        }
                    }
                    
                    // Partial duplicate directories section
                    if !photoLibrary.directoryDuplicates.isEmpty {
                        Text("Directories with Duplicates")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        ForEach(photoLibrary.directoryDuplicates, id: \.fullPath) { dirInfo in
                            DirectoryDuplicateRowView(
                                dirInfo: dirInfo,
                                isExpanded: expandedDirectories.contains(dirInfo.fullPath),
                                selectedPhoto: $selectedPhoto,
                                onToggleExpanded: {
                                    toggleDirectoryExpansion(for: dirInfo)
                                }
                            )
                            
                            Divider()
                        }
                    }
                    }
                }
                .frame(width: sidebarWidth - 20)
                .padding(.horizontal, 10)
        }
        .navigationTitle("\(photoLibrary.directoryDuplicates.count) Dirs with Duplicates")
    }
    
    private func toggleDirectoryExpansion(for dirInfo: DirectoryDuplicateInfo) {
        if expandedDirectories.contains(dirInfo.fullPath) {
            expandedDirectories.remove(dirInfo.fullPath)
        } else {
            expandedDirectories.insert(dirInfo.fullPath)
        }
    }
    
    private func toggleCompleteDuplicateExpansion(for completeDir: CompleteDuplicateDirectory) {
        let primaryPath = completeDir.primaryDirectory.fullPath
        if expandedCompleteDuplicates.contains(primaryPath) {
            expandedCompleteDuplicates.remove(primaryPath)
        } else {
            expandedCompleteDuplicates.insert(primaryPath)
        }
    }
}

struct CompleteDuplicateDirectoryRowView: View {
    let completeDir: CompleteDuplicateDirectory
    let isExpanded: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggleExpanded: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    @State private var directoryToDelete: DirectoryInfo?
    @State private var expandedDirectoryContents: Set<String> = []
    
    private var totalWastedSize: String {
        let wastedSize = completeDir.totalSize * Int64(completeDir.duplicateDirectories.count)
        return ByteCountFormatter().string(fromByteCount: wastedSize)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggleExpanded()
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "folder.fill.badge.questionmark")
                                .foregroundColor(.red)
                            
                            Text("\(completeDir.duplicateDirectories.count) complete duplicates")
                                .fontWeight(.medium)
                        }
                        
                        Text("Wasting \(totalWastedSize)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(completeDir.primaryDirectory.fullPath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(completeDir.fileCount) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Show all directories (primary + duplicates)
                    ForEach(completeDir.allDirectories, id: \.fullPath) { dirInfo in
                        DirectoryRowWithContents(
                            dirInfo: dirInfo,
                            isPrimary: dirInfo.fullPath == completeDir.primaryDirectory.fullPath,
                            isExpanded: expandedDirectoryContents.contains(dirInfo.fullPath),
                            selectedPhoto: $selectedPhoto,
                            onToggleExpanded: {
                                if expandedDirectoryContents.contains(dirInfo.fullPath) {
                                    expandedDirectoryContents.remove(dirInfo.fullPath)
                                } else {
                                    expandedDirectoryContents.insert(dirInfo.fullPath)
                                }
                            },
                            onDelete: {
                                directoryToDelete = dirInfo
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .alert("Move Directory to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                if let dirInfo = directoryToDelete {
                    photoLibrary.moveDirectoryToTrash(dirInfo)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let dirInfo = directoryToDelete {
                Text("Are you sure you want to move '\(dirInfo.fullPath)' to the Trash?\n\nThis will move \(dirInfo.files.count) file(s) to the Trash and remove them from the database.")
            }
        }
    }
}

struct DirectoryRowWithContents: View {
    let dirInfo: DirectoryInfo
    let isPrimary: Bool
    let isExpanded: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggleExpanded: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    onToggleExpanded()
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(isPrimary ? "Primary" : "Duplicate")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(isPrimary ? .blue : .orange)
                                
                                Text("(\(dirInfo.files.count) files)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(dirInfo.fullPath)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Move directory to trash")
            }
            
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(dirInfo.files.prefix(10)) { file in
                        HStack(spacing: 6) {
                            // Thumbnail with hover and click
                            ReusableHoverThumbnail(photo: file, size: 32, onTap: {
                                selectedPhoto = file
                            })
                            .environmentObject(photoLibrary)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.fileName)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(4)
                        .padding(.leading, 20)
                    }
                    
                    if dirInfo.files.count > 10 {
                        Text("... and \(dirInfo.files.count - 10) more files")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DirectoryDuplicateRowView: View {
    let dirInfo: DirectoryDuplicateInfo
    let isExpanded: Bool
    @Binding var selectedPhoto: PhotoFile?
    let onToggleExpanded: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAllAlert = false
    @State private var otherDirectoriesWithSameFiles: [String: Int] = [:]
    @State private var duplicatesInSameDirectory: Int = 0
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    
    private var wastedSizeStr: String {
        return ByteCountFormatter().string(fromByteCount: dirInfo.wastedSize)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggleExpanded()
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.orange)
                            
                            Text("\(dirInfo.duplicateFileCount) duplicates")
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("\(String(format: "%.1f", dirInfo.duplicatePercentage))% duplicates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("• Wasting \(wastedSizeStr)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(dirInfo.fullPath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(dirInfo.fileCount) total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Button {
                                openInFinder(dirInfo.fullPath)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open in Finder")
                            
                            Button {
                                showingDeleteAllAlert = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "trash.fill")
                                    Text("Delete All")
                                }
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Move all \(dirInfo.duplicateFileCount) duplicates to trash")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Show summary of directories that share duplicate files
                    if isAnalyzing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing \(dirInfo.duplicateFileCount) duplicate locations...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    } else if let error = analysisError {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Analysis failed")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task {
                                    await findOtherDirectories()
                                }
                            }
                            .font(.caption2)
                        }
                        .padding(.leading, 20)
                    } else if duplicatesInSameDirectory > 0 && otherDirectoriesWithSameFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(duplicatesInSameDirectory) duplicate sets within this directory")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Files with the same content (hash) but possibly different names")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Show duplicate groups within same directory
                        SameDirectoryDuplicatesView(
                            dirInfo: dirInfo,
                            selectedPhoto: $selectedPhoto
                        )
                        .padding(.leading, 20)
                    } else if otherDirectoriesWithSameFiles.isEmpty {
                        // Check if there are actual same-directory duplicates to show
                        let duplicateGroupsInDir = Dictionary(grouping: dirInfo.files, by: { $0.fileHash })
                            .filter { $0.value.count > 1 }
                        
                        if duplicateGroupsInDir.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No duplicate locations found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("These files are unique to this directory")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                        } else {
                            // Show same-directory duplicates instead
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No files exist in multiple directories")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("However, this directory has \(duplicateGroupsInDir.count) duplicate sets within itself")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            SameDirectoryDuplicatesView(
                                dirInfo: dirInfo,
                                selectedPhoto: $selectedPhoto
                            )
                            .padding(.leading, 20)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This directory has \(dirInfo.duplicateFileCount) files that are duplicates.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("These duplicate files are also found in:")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.leading, 20)
                        
                        ForEach(Array(otherDirectoriesWithSameFiles.keys.sorted()), id: \.self) { otherDir in
                            if let count = otherDirectoriesWithSameFiles[otherDir] {
                                DirectoryDuplicateSummaryRow(
                                    sourceDirectoryPath: dirInfo.fullPath,
                                    targetDirectoryPath: otherDir,
                                    sharedFileCount: count,
                                    totalDuplicatesInSource: dirInfo.duplicateFileCount,
                                    sourceFiles: dirInfo.files,
                                    selectedPhoto: $selectedPhoto
                                )
                            }
                        }
                        .padding(.leading, 20)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Show individual files in a collapsible section
                        DisclosureGroup("View \(dirInfo.duplicateFileCount) duplicate files") {
                            ForEach(dirInfo.files) { file in
                                CompactDuplicateFileRow(file: file, selectedPhoto: $selectedPhoto)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onChange(of: isExpanded) { _, newValue in
            if newValue && otherDirectoriesWithSameFiles.isEmpty && duplicatesInSameDirectory == 0 && !isAnalyzing {
                print("🎯 Directory expanded, starting analysis")
                Task {
                    await findOtherDirectories()
                }
            }
        }
        .alert("Delete All Duplicates", isPresented: $showingDeleteAllAlert) {
            Button("Move All to Trash", role: .destructive) {
                photoLibrary.deleteAllDuplicatesInDirectory(dirInfo)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to move all \(dirInfo.duplicateFileCount) duplicate files in this directory to the Trash?\n\nDirectory: \(dirInfo.fullPath)\n\nFiles will be moved to macOS Trash and removed from the database.")
        }
    }
    
    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    private func findOtherDirectories() async {
        await MainActor.run {
            isAnalyzing = true
            analysisError = nil
        }
        
        // Capture needed values on main actor
        let files = dirInfo.files
        let currentDirPath = dirInfo.fullPath
        let duplicateGroups = photoLibrary.duplicateGroups
        let rootDirectories = photoLibrary.rootDirectories
        
        print("🔍 Starting analysis for \(currentDirPath) with \(files.count) files")
        print("📊 Total duplicate groups: \(duplicateGroups.count)")
        
        // Run analysis in background
        let result = await Task.detached(priority: .userInitiated) { () -> (otherDirs: [String: Int], sameDirCount: Int) in
            var directoryCount: [String: Int] = [:]
            var sameDirectoryDuplicates = 0
            
            // Create a hash map for faster lookups
            let duplicateGroupsByHash = Dictionary(grouping: duplicateGroups, by: { $0.fileHash })
            
            print("🗂 Created hash map with \(duplicateGroupsByHash.count) entries")
            
            // For each duplicate file in this directory, find where else it exists
            for (index, file) in files.enumerated() {
                if index % 100 == 0 {
                    print("📝 Processing file \(index + 1)/\(files.count)")
                }
                
                // Find all locations of this file using hash map
                if let groups = duplicateGroupsByHash[file.fileHash], let duplicateGroup = groups.first {
                    print("✅ Found duplicate group for \(file.fileName) with \(duplicateGroup.files.count) locations")
                    
                    var foundInOtherDir = false
                    for otherFile in duplicateGroup.files {
                        // Get the directory path for this other file
                        let rootDir = rootDirectories.first(where: { $0.id == otherFile.rootDirectoryId })
                        guard let rootPath = rootDir?.path else { 
                            print("⚠️ No root path for file \(otherFile.fileName)")
                            continue 
                        }
                        
                        let directoryPath = (otherFile.relativePath as NSString).deletingLastPathComponent
                        let fullDirPath = (rootPath as NSString).appendingPathComponent(directoryPath)
                        
                        // Skip if it's the current directory
                        if fullDirPath == currentDirPath {
                            continue
                        }
                        
                        foundInOtherDir = true
                        // Count how many files from our directory exist in this other directory
                        directoryCount[fullDirPath, default: 0] += 1
                        print("📍 Found duplicate in: \(fullDirPath)")
                    }
                    
                    // If this file has duplicates but none in other directories, it's a same-directory duplicate
                    if !foundInOtherDir {
                        sameDirectoryDuplicates += 1
                        print("🔁 File \(file.fileName) has duplicates only within same directory")
                    }
                } else {
                    print("❌ No duplicate group found for \(file.fileName) with hash \(file.fileHash)")
                }
            }
            
            print("✨ Analysis complete. Found \(directoryCount.count) other directories, \(sameDirectoryDuplicates) same-dir duplicates")
            return (directoryCount, sameDirectoryDuplicates)
        }.value
        
        await MainActor.run {
            print("📥 Updating UI with \(result.otherDirs.count) directories, \(result.sameDirCount) same-dir duplicates")
            self.otherDirectoriesWithSameFiles = result.otherDirs
            self.duplicatesInSameDirectory = result.sameDirCount
            self.isAnalyzing = false
        }
    }
}

struct DuplicateFileWithLocationsView: View {
    let file: PhotoFile
    let currentDirectoryPath: String
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var isExpanded = false
    @State private var allLocations: [PhotoFile] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main file row
            Button {
                isExpanded.toggle()
                if isExpanded && allLocations.isEmpty {
                    loadAllLocations()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Thumbnail with hover and click
                    ReusableHoverThumbnail(photo: file, size: 32, onTap: {
                        selectedPhoto = file
                    })
                    .environmentObject(photoLibrary)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.fileName)
                            .font(.caption)
                            .lineLimit(1)
                        
                        HStack {
                            Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            if !allLocations.isEmpty {
                                Text("• \(allLocations.count) locations")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
            )
            
            // Show all locations when expanded
            if isExpanded && !allLocations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found in \(allLocations.count) locations:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 40)
                    
                    ForEach(allLocations) { location in
                        DuplicateLocationRow(
                            file: location,
                            isCurrentDirectory: getDirectoryPath(for: location) == currentDirectoryPath,
                            selectedPhoto: $selectedPhoto
                        )
                    }
                }
                .padding(.leading, 40)
                .padding(.top, 4)
            }
        }
    }
    
    private func loadAllLocations() {
        // Find all files with the same hash
        let allFiles = photoLibrary.duplicateGroups
            .first(where: { $0.fileHash == file.fileHash })?
            .files ?? []
        
        allLocations = allFiles.sorted { getFullPath(for: $0) < getFullPath(for: $1) }
    }
    
    private func getFullPath(for photo: PhotoFile) -> String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return photo.relativePath }
        // Return full path including filename
        return (rootPath as NSString).appendingPathComponent(photo.relativePath)
    }
    
    private func getDirectoryPath(for photo: PhotoFile) -> String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return (photo.relativePath as NSString).deletingLastPathComponent }
        // Return directory path only (without filename)
        let directoryPath = (photo.relativePath as NSString).deletingLastPathComponent
        return (rootPath as NSString).appendingPathComponent(directoryPath)
    }
}

struct DuplicateLocationRow: View {
    let file: PhotoFile
    let isCurrentDirectory: Bool
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    
    private var fullPath: String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == file.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return file.relativePath }
        return (rootPath as NSString).appendingPathComponent(file.relativePath)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrentDirectory ? "folder.fill" : "folder")
                .font(.caption2)
                .foregroundColor(isCurrentDirectory ? .blue : .secondary)
            
                VStack(alignment: .leading, spacing: 1) {
                Text(fullPath)
                    .font(.caption2)
                    .foregroundColor(isCurrentDirectory ? .blue : .primary)
                
                if let dateTaken = file.exifDateTaken {
                    Text(dateTaken, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption2)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Move this file to trash")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrentDirectory ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        )
        .alert("Move Photo to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                photoLibrary.movePhotoToTrash(file)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to move '\(file.fileName)' to the Trash?\n\nLocation: \(fullPath)\n\nThis will move the file to the Trash and remove it from the database.")
        }
    }
}

struct DirectoryDuplicateSummaryRow: View {
    let sourceDirectoryPath: String
    let targetDirectoryPath: String
    let sharedFileCount: Int
    let totalDuplicatesInSource: Int
    let sourceFiles: [PhotoFile]  // Files from the source directory
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var isExpanded = false
    @State private var overlappingFiles: [(source: PhotoFile, target: PhotoFile)] = []
    @State private var showingDeleteSourceConfirmation = false
    @State private var showingDeleteTargetConfirmation = false
    @State private var filesToDeleteInSheet: [PhotoFile] = []
    @State private var otherLocationsInSheet: [PhotoFile] = []
    
    private var percentage: Double {
        guard totalDuplicatesInSource > 0 else { return 0 }
        return Double(sharedFileCount) / Double(totalDuplicatesInSource) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
                if isExpanded && overlappingFiles.isEmpty {
                    findOverlappingFiles()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(targetDirectoryPath)
                            .font(.caption)
                            .textSelection(.enabled)
                        
                        HStack {
                            Text("\(sharedFileCount) shared duplicate files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• \(String(format: "%.0f", percentage))% of this dir's duplicates")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.1))
            )
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // If overlappingFiles is empty after expansion, this means no cross-directory duplicates
                    if overlappingFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No files actually exist in both directories")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                            
                            Text("These appear to be same-directory duplicates:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                            
                            // Show same-directory duplicates instead
                            SameDirectoryDuplicatesView(
                                dirInfo: DirectoryDuplicateInfo(
                                    directoryPath: sourceDirectoryPath,
                                    fullPath: sourceDirectoryPath,
                                    fileCount: sourceFiles.count,
                                    duplicateFileCount: sourceFiles.count,
                                    totalSize: sourceFiles.reduce(0) { $0 + $1.fileSize },
                                    wastedSize: 0,
                                    files: sourceFiles,
                                    rootDirectoryId: sourceFiles.first?.rootDirectoryId ?? 0
                                ),
                                selectedPhoto: $selectedPhoto
                            )
                        }
                    } else {
                        // We have actual overlapping files - show delete options
                        VStack(spacing: 8) {
                        Text("Delete duplicates from:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            // Delete from this directory (target)
                            Button {
                                let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("photomanager_debug.txt")
                                var log = "=== DELETE TARGET BUTTON CLICKED ===\n"
                                log += "Time: \(Date())\n"
                                log += "Source: \(sourceDirectoryPath)\n"
                                log += "Target: \(targetDirectoryPath)\n"
                                log += "Shared file count: \(sharedFileCount)\n"
                                
                                if overlappingFiles.isEmpty {
                                    log += "overlappingFiles is EMPTY, calling findOverlappingFiles()\n"
                                    findOverlappingFiles()
                                    log += "After findOverlappingFiles: \(overlappingFiles.count) items\n"
                                } else {
                                    log += "overlappingFiles already has \(overlappingFiles.count) items\n"
                                }
                                
                                if overlappingFiles.isEmpty {
                                    log += "ERROR: Still empty after findOverlappingFiles!\n"
                                } else {
                                    filesToDeleteInSheet = overlappingFiles.map { $0.target }
                                    otherLocationsInSheet = overlappingFiles.map { $0.source }
                                    log += "Captured \(filesToDeleteInSheet.count) files for sheet\n"
                                    if !filesToDeleteInSheet.isEmpty {
                                        log += "First file: \(filesToDeleteInSheet[0].fileName)\n"
                                    }
                                }
                                
                                try? log.write(to: logFile, atomically: true, encoding: .utf8)
                                NSWorkspace.shared.activateFileViewerSelecting([logFile])
                                
                                showingDeleteTargetConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("This Directory")
                                            .fontWeight(.medium)
                                        Text(targetDirectoryPath)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .help("Delete \(sharedFileCount) duplicate files from this directory. Files in the source directory will be kept.")
                            
                            // Delete from source directory
                            Button {
                                if overlappingFiles.isEmpty {
                                    print("⚠️ overlappingFiles is empty, finding files first")
                                    findOverlappingFiles()
                                } else {
                                    print("✅ overlappingFiles already has \(overlappingFiles.count) items")
                                }
                                print("Opening delete source confirmation with \(overlappingFiles.count) files")
                                if overlappingFiles.isEmpty {
                                    print("❌ ERROR: Still empty after findOverlappingFiles!")
                                } else {
                                    // Capture the arrays NOW for the sheet
                                    filesToDeleteInSheet = overlappingFiles.map { $0.source }
                                    otherLocationsInSheet = overlappingFiles.map { $0.target }
                                    print("📦 Captured \(filesToDeleteInSheet.count) files for sheet")
                                }
                                showingDeleteSourceConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Source Directory")
                                            .fontWeight(.medium)
                                        Text(sourceDirectoryPath)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .help("Delete \(sharedFileCount) duplicate files from the source directory. Files in this directory will be kept.")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(6)
                        
                        // Show overlapping files list
                        Text("Overlapping files:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        
                        ForEach(overlappingFiles.prefix(10), id: \.source.id) { pair in
                            OverlappingFileRow(sourceFile: pair.source, targetFile: pair.target, selectedPhoto: $selectedPhoto)
                        }
                        
                        if overlappingFiles.count > 10 {
                            Text("... and \(overlappingFiles.count - 10) more files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.leading, 30)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingDeleteTargetConfirmation) {
            DuplicateDeletionConfirmationView(
                filesToDelete: filesToDeleteInSheet,
                otherLocations: otherLocationsInSheet,
                directoryPath: targetDirectoryPath,
                onConfirm: {
                    deleteFilesFromTargetDirectory()
                    showingDeleteTargetConfirmation = false
                },
                onCancel: {
                    showingDeleteTargetConfirmation = false
                },
                selectedPhoto: $selectedPhoto
            )
            .environmentObject(photoLibrary)
        }
        .sheet(isPresented: $showingDeleteSourceConfirmation) {
            DuplicateDeletionConfirmationView(
                filesToDelete: filesToDeleteInSheet,
                otherLocations: otherLocationsInSheet,
                directoryPath: sourceDirectoryPath,
                onConfirm: {
                    deleteFilesFromSourceDirectory()
                    showingDeleteSourceConfirmation = false
                },
                onCancel: {
                    showingDeleteSourceConfirmation = false
                },
                selectedPhoto: $selectedPhoto
            )
            .environmentObject(photoLibrary)
        }
    }
    
    private func findOverlappingFiles() {
        print("🔍 findOverlappingFiles called")
        print("   Source: \(sourceDirectoryPath)")
        print("   Target: \(targetDirectoryPath)")
        print("   Shared file count: \(sharedFileCount)")
        
        var pairs: [(source: PhotoFile, target: PhotoFile)] = []
        
        // Find all duplicate groups and locate overlapping files
        print("   Total duplicate groups: \(photoLibrary.duplicateGroups.count)")
        for group in photoLibrary.duplicateGroups {
            // Find files in target directory
            let filesInTarget = group.files.filter { file in
                let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == file.rootDirectoryId })
                guard let rootPath = rootDir?.path else { return false }
                let dirPath = (file.relativePath as NSString).deletingLastPathComponent
                let fullDirPath = (rootPath as NSString).appendingPathComponent(dirPath)
                return fullDirPath == targetDirectoryPath
            }
            
            // Find files in source directory
            let filesInSource = group.files.filter { file in
                let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == file.rootDirectoryId })
                guard let rootPath = rootDir?.path else { return false }
                let dirPath = (file.relativePath as NSString).deletingLastPathComponent
                let fullDirPath = (rootPath as NSString).appendingPathComponent(dirPath)
                return fullDirPath == sourceDirectoryPath
            }
            
            // If this file exists in both directories, add to pairs
            if let targetFile = filesInTarget.first, let sourceFile = filesInSource.first {
                print("   ✅ Found pair: \(sourceFile.fileName) <-> \(targetFile.fileName)")
                pairs.append((source: sourceFile, target: targetFile))
            } else if filesInTarget.count > 0 || filesInSource.count > 0 {
                print("   ⚠️ Mismatch - Target: \(filesInTarget.count), Source: \(filesInSource.count) for hash \(String(group.fileHash.prefix(8)))")
            }
        }
        
        print("   📊 Total pairs found: \(pairs.count)")
        overlappingFiles = pairs.sorted { $0.source.fileName < $1.source.fileName }
        print("   ✨ overlappingFiles set to \(overlappingFiles.count) items")
    }
    
    private func deleteFilesFromTargetDirectory() {
        for pair in overlappingFiles {
            photoLibrary.movePhotoToTrash(pair.target)
        }
    }
    
    private func deleteFilesFromSourceDirectory() {
        for pair in overlappingFiles {
            photoLibrary.movePhotoToTrash(pair.source)
        }
    }
}

struct OverlappingFileRow: View {
    let sourceFile: PhotoFile
    let targetFile: PhotoFile
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    private var targetFullPath: String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == targetFile.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return targetFile.relativePath }
        return (rootPath as NSString).appendingPathComponent(targetFile.relativePath)
    }
    
    private var sourceDirectoryPath: String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == sourceFile.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return (sourceFile.relativePath as NSString).deletingLastPathComponent }
        let directoryPath = (sourceFile.relativePath as NSString).deletingLastPathComponent
        return (rootPath as NSString).appendingPathComponent(directoryPath)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail with hover and click
            ReusableHoverThumbnail(photo: targetFile, size: 30, onTap: {
                selectedPhoto = targetFile
            })
            .environmentObject(photoLibrary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(targetFile.fileName)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(formatFileSize(targetFile.fileSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Also in: \(sourceDirectoryPath)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(4)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SameDirectoryDuplicatesView: View {
    let dirInfo: DirectoryDuplicateInfo
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteSelectedAlert = false
    @State private var selectedFilesForDeletion: Set<Int64> = []  // Track selected file IDs
    
    // Group files by hash to show duplicate sets
    private var duplicateGroups: [String: [PhotoFile]] {
        Dictionary(grouping: dirInfo.files, by: { $0.fileHash })
            .filter { $0.value.count > 1 }
    }
    
    // Get all duplicates except keep the first one in each group
    private var duplicatesToDelete: [PhotoFile] {
        duplicateGroups.values.flatMap { files in
            Array(files.dropFirst()) // Keep first, delete rest
        }
    }
    
    // Get selected files for deletion
    private var selectedFiles: [PhotoFile] {
        dirInfo.files.filter { file in
            if let id = file.id {
                return selectedFilesForDeletion.contains(id)
            }
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Action buttons
            HStack {
                Text("\(duplicateGroups.count) duplicate sets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !selectedFilesForDeletion.isEmpty {
                    Text("• \(selectedFilesForDeletion.count) selected")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if !selectedFilesForDeletion.isEmpty {
                    Button {
                        showingDeleteSelectedAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text("Delete Selected (\(selectedFilesForDeletion.count))")
                        }
                        .font(.caption2)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Button {
                        selectedFilesForDeletion.removeAll()
                    } label: {
                        Text("Clear Selection")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    showingDeleteAllAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Delete All Duplicates")
                    }
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Keep first file in each set, delete the rest (\(duplicatesToDelete.count) files)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(6)
            
            ForEach(Array(duplicateGroups.keys.sorted()), id: \.self) { hash in
                if let files = duplicateGroups[hash] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            Text("\(files.count) copies (\(String(hash.prefix(12)))...)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(ByteCountFormatter().string(fromByteCount: files[0].fileSize))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                        
                        // Show each file in the duplicate set
                        ForEach(files) { file in
                            HStack(spacing: 6) {
                                // Checkbox for selection
                                if let fileId = file.id {
                                    Button {
                                        if selectedFilesForDeletion.contains(fileId) {
                                            selectedFilesForDeletion.remove(fileId)
                                        } else {
                                            selectedFilesForDeletion.insert(fileId)
                                        }
                                    } label: {
                                        Image(systemName: selectedFilesForDeletion.contains(fileId) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedFilesForDeletion.contains(fileId) ? .blue : .gray)
                                            .font(.body)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                // Thumbnail with hover and click
                                ReusableHoverThumbnail(photo: file, size: 40, onTap: {
                                    selectedPhoto = file
                                })
                                .environmentObject(photoLibrary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.fileName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 4) {
                                        if let dateTaken = file.exifDateTaken {
                                            Text(dateTaken, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    photoLibrary.movePhotoToTrash(file)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.caption2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Move to trash")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                selectedFilesForDeletion.contains(file.id ?? 0) 
                                    ? Color.blue.opacity(0.1) 
                                    : Color.gray.opacity(0.05)
                            )
                            .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .alert("Delete Same-Directory Duplicates", isPresented: $showingDeleteAllAlert) {
            Button("Keep First, Delete \(duplicatesToDelete.count) Others", role: .destructive) {
                for file in duplicatesToDelete {
                    photoLibrary.movePhotoToTrash(file)
                }
                selectedFilesForDeletion.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will keep the first file in each duplicate set and delete the others.\n\n\(duplicatesToDelete.count) files will be moved to the Trash.\n\nYou can restore them from Trash if needed.")
        }
        .alert("Delete Selected Files", isPresented: $showingDeleteSelectedAlert) {
            Button("Move \(selectedFiles.count) Files to Trash", role: .destructive) {
                for file in selectedFiles {
                    photoLibrary.movePhotoToTrash(file)
                }
                selectedFilesForDeletion.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Move \(selectedFiles.count) selected files to the Trash?\n\nYou can restore them from Trash if needed.")
        }
    }
}

struct CompactDuplicateFileRow: View {
    let file: PhotoFile
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Thumbnail with hover and click
            ReusableHoverThumbnail(photo: file, size: 24, onTap: {
                selectedPhoto = file
            })
            .environmentObject(photoLibrary)
            
            Text(file.fileName)
                .font(.caption2)
                .lineLimit(1)
            
            Spacer()
            
            Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
        .alert("Move Photo to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                photoLibrary.movePhotoToTrash(file)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to move '\(file.fileName)' to the Trash?")
        }
    }
}
