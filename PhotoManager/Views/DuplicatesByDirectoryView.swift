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
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(dirInfo.fileCount) total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
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
                            Text("\(duplicatesInSameDirectory) files have duplicates within this directory")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("These files are duplicated internally (not found in other directories)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Show individual files
                        DisclosureGroup("View \(dirInfo.duplicateFileCount) duplicate files") {
                            ForEach(dirInfo.files) { file in
                                CompactDuplicateFileRow(file: file, selectedPhoto: $selectedPhoto)
                            }
                        }
                        .padding(.leading, 20)
                    } else if otherDirectoriesWithSameFiles.isEmpty {
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
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var isExpanded = false
    @State private var overlappingFiles: [(source: PhotoFile, target: PhotoFile)] = []
    @State private var showingDeleteSourceAlert = false
    @State private var showingDeleteTargetAlert = false
    
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
                    // Bulk delete options
                    HStack(spacing: 12) {
                        Button {
                            showingDeleteTargetAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("Delete \(sharedFileCount) duplicate files from this directory")
                            }
                            .font(.caption2)
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete only the duplicate files found in both directories. Other files in this directory will be kept.")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(4)
                    
                    // Show overlapping files
                    if !overlappingFiles.isEmpty {
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
        .alert("Delete Duplicate Files", isPresented: $showingDeleteTargetAlert) {
            Button("Move \(sharedFileCount) Files to Trash", role: .destructive) {
                deleteFilesFromTargetDirectory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will move \(sharedFileCount) duplicate files from:\n'\(targetDirectoryPath)'\nto the Trash.\n\nThese are copies of files that also exist in:\n'\(sourceDirectoryPath)'\n\nOnly the duplicate files will be deleted. Other unique files in the directory will be kept.")
        }
    }
    
    private func findOverlappingFiles() {
        var pairs: [(source: PhotoFile, target: PhotoFile)] = []
        
        // Find all duplicate groups and locate overlapping files
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
                pairs.append((source: sourceFile, target: targetFile))
            }
        }
        
        overlappingFiles = pairs.sorted { $0.source.fileName < $1.source.fileName }
    }
    
    private func deleteFilesFromTargetDirectory() {
        for pair in overlappingFiles {
            photoLibrary.movePhotoToTrash(pair.target)
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
