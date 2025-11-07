import SwiftUI

struct DirectoryComparisonView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var selectedComparison: DirectoryPair?
    @State private var selectedFilesForDeletion: Set<Int64> = []
    @State private var showingDeleteConfirmation = false
    @State private var isLoading = false
    @State private var loadedPairs: [DirectoryPair] = []
    @State private var needsRefresh = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        Text("Analyzing directories...")
                            .font(.headline)
                    } else {
                        Text("\(loadedPairs.count) Directory Pairs with Duplicates")
                            .font(.headline)
                    }
                    
                    Text("Compare directories with shared duplicate files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            if selectedComparison == nil {
                // List of directory pairs
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Finding directory pairs...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if loadedPairs.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.green)
                                    
                                    Text("No Cross-Directory Duplicates")
                                        .font(.headline)
                                    
                                    Text("All duplicates are within single directories.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(40)
                            } else {
                                ForEach(loadedPairs) { pair in
                                    DirectoryPairRow(
                                        pair: pair,
                                        selectedPhoto: $selectedPhoto,
                                        onSelect: {
                                            openComparisonWindow(for: pair)
                                        }
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Directory Comparison")
        .onAppear {
            // Load if empty, or refresh if marked as stale
            if loadedPairs.isEmpty && !isLoading {
                loadDirectoryPairs()
            } else if needsRefresh && !isLoading {
                print("🔄 Refreshing directory pairs list after changes")
                needsRefresh = false
                loadDirectoryPairs()
            }
        }
        .onChange(of: photoLibrary.duplicateGroups.count) { oldCount, newCount in
            // Duplicate groups changed (e.g., files deleted)
            print("⏳ Duplicate groups changed from \(oldCount) to \(newCount)")
            needsRefresh = true
            
            // Always auto-refresh after deletions (we use independent windows now)
            if !isLoading {
                print("🔄 Auto-refreshing directory pairs list after 1 second delay")
                Task {
                    // Small delay to allow batch deletions to complete
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    
                    await MainActor.run {
                        if needsRefresh && !isLoading {
                            print("✅ Executing refresh now...")
                            needsRefresh = false
                            loadDirectoryPairs()
                        }
                    }
                }
            }
        }
    }
    
    private func loadDirectoryPairs() {
        isLoading = true
        print("🔄 Starting directory pairs calculation...")
        
        Task {
            // Add timeout protection
            let pairs = await withTimeout(seconds: 30) {
                await calculateDirectoryPairs()
            }
            
            await MainActor.run {
                loadedPairs = pairs ?? []
                isLoading = false
                if pairs == nil {
                    print("⏰ Directory pairs calculation timed out after 30 seconds")
                } else {
                    print("✅ Directory pairs calculation completed")
                }
            }
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        try? await withThrowingTaskGroup(of: T?.self) { group in
            // Add the actual operation
            group.addTask {
                await operation()
            }
            
            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            // Return first result
            if let result = try await group.next() {
                group.cancelAll()
                return result
            }
            return nil
        }
    }
    
    private func calculateDirectoryPairs() async -> [DirectoryPair] {
        return await Task.detached {
            // Build a map of directory -> [hash -> count]
            var dirHashCounts: [String: [String: Int]] = [:]
            
            // Capture data on main actor
            let duplicateGroups = await MainActor.run { photoLibrary.duplicateGroups }
            let rootDirectories = await MainActor.run { photoLibrary.rootDirectories }
            
            print("📋 Captured \(rootDirectories.count) root directories")
            for root in rootDirectories {
                print("   Root ID \(root.id): \(root.path)")
            }
            
            // Safety check: limit processing to prevent memory overflow
            let maxGroupsToProcess = min(duplicateGroups.count, 10000)
            if duplicateGroups.count > maxGroupsToProcess {
                print("⚠️ WARNING: Too many duplicate groups (\(duplicateGroups.count)). Processing only first \(maxGroupsToProcess)")
            }
            
            // First pass: count files per hash per directory
            var uniqueRootIds: Set<Int64> = []
            var skippedFiles = 0
            var processedGroups = 0
            let groupsToProcess = Array(duplicateGroups.prefix(maxGroupsToProcess))
            
            for group in groupsToProcess where group.files.count > 1 {
                let hash = group.fileHash
                for file in group.files {
                    uniqueRootIds.insert(file.rootDirectoryId)
                    // ONLY use absolute paths
                    if let dirPath = file.getAbsoluteDirectoryPath(rootDirectories: rootDirectories) {
                        dirHashCounts[dirPath, default: [:]][hash, default: 0] += 1
                    } else {
                        skippedFiles += 1
                    }
                }
                processedGroups += 1
                if processedGroups % 100 == 0 {
                    print("⏳ Processed \(processedGroups)/\(groupsToProcess.count) duplicate groups")
                }
            }
            
            print("🔑 Unique root IDs found in files: \(uniqueRootIds.sorted())")
            if skippedFiles > 0 {
                print("⚠️ Skipped \(skippedFiles) files due to missing root directories")
            }
            
            // Second pass: find directory pairs that share hashes
            var pairCounts: [Set<String>: (count: Int, wasted: Int64)] = [:]
            let directories = Array(dirHashCounts.keys)
            
            for i in 0..<directories.count {
                for j in (i+1)..<directories.count {
                    let dir1 = directories[i]
                    let dir2 = directories[j]
                    
                    guard let hashes1 = dirHashCounts[dir1],
                          let hashes2 = dirHashCounts[dir2] else { continue }
                    
                    // Find common hashes
                    let commonHashes = Set(hashes1.keys).intersection(Set(hashes2.keys))
                    
                    if !commonHashes.isEmpty {
                        var totalCount = 0
                        var totalWasted: Int64 = 0
                        
                        for hash in commonHashes {
                            let count1 = hashes1[hash] ?? 0
                            let count2 = hashes2[hash] ?? 0
                            totalCount += count1 + count2
                            
                            // Find file size for this hash
                            if let group = duplicateGroups.first(where: { $0.fileHash == hash }),
                               let fileSize = group.files.first?.fileSize {
                                totalWasted += fileSize * Int64(count1 + count2 - 1)
                            }
                        }
                        
                        let pairKey = Set([dir1, dir2])
                        pairCounts[pairKey] = (totalCount, totalWasted)
                    }
                }
            }
            
            // Convert to DirectoryPair array
            let pairs = pairCounts.map { (dirs, stats) in
                let dirsArray = Array(dirs).sorted()
                let pair = DirectoryPair(
                    directory1: dirsArray[0],
                    directory2: dirsArray[1],
                    sharedDuplicateCount: stats.count,
                    wastedSpace: stats.wasted
                )
                print("✅ Created pair: \(dirsArray[0].split(separator: "/").suffix(2).joined(separator: "/")) <-> \(dirsArray[1].split(separator: "/").suffix(2).joined(separator: "/"))")
                print("   Full Dir1: \(dirsArray[0])")
                print("   Full Dir2: \(dirsArray[1])")
                return pair
            }.sorted { $0.sharedDuplicateCount > $1.sharedDuplicateCount }
            
            print("🎯 Total directory pairs found: \(pairs.count)")
            return pairs
        }.value
    }
    
    private func getDirectoryPath(for photo: PhotoFile) -> String? {
        return photo.getAbsoluteDirectoryPath(rootDirectories: photoLibrary.rootDirectories)
    }
    
    private func openComparisonWindow(for pair: DirectoryPair) {
        print("👀 Opening comparison window for:")
        print("   Dir1: \(pair.directory1)")
        print("   Dir2: \(pair.directory2)")
        
        // Create new window - each window is independent
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Compare: \(pair.directory1.split(separator: "/").last ?? "") vs \(pair.directory2.split(separator: "/").last ?? "")"
        window.center()
        
        // Create a window controller to keep the window alive
        let windowController = NSWindowController(window: window)
        
        // Create comparison view
        let comparisonView = DirectoryComparisonDetailView(
            pair: pair,
            selectedPhoto: $selectedPhoto,
            windowController: windowController,
            onBack: { [weak window] in
                print("⬅️ Closing comparison window")
                window?.close()
            }
        )
        .environmentObject(photoLibrary)
        
        window.contentView = NSHostingView(rootView: comparisonView)
        windowController.showWindow(nil)
        
        print("✅ Comparison window created and shown")
    }
}

struct DirectoryPair: Identifiable {
    let id = UUID()
    let directory1: String
    let directory2: String
    let sharedDuplicateCount: Int
    let wastedSpace: Int64
}

struct DirectoryPairRow: View {
    let pair: DirectoryPair
    @Binding var selectedPhoto: PhotoFile?
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(pair.directory1)
                            .font(.caption)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(pair.sharedDuplicateCount) shared duplicates")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 20)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(pair.directory2)
                            .font(.caption)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ByteCountFormatter().string(fromByteCount: pair.wastedSpace))
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
        .buttonStyle(.plain)
    }
}

struct DirectoryComparisonDetailView: View {
    let pair: DirectoryPair
    @Binding var selectedPhoto: PhotoFile?
    let windowController: NSWindowController  // Keeps the window alive
    let onBack: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var selectedForDeletion: Set<Int64> = []
    @State private var showingDeleteConfirmation = false
    @State private var duplicatedFiles: [(file1: PhotoFile, file2: PhotoFile)] = []
    @State private var isLoadingFiles = true
    @State private var loadError: String?
    @State private var loadTask: Task<Void, Never>? = nil
    
    private var selectedFiles: [PhotoFile] {
        photoLibrary.duplicateGroups
            .flatMap { $0.files }
            .filter { file in
                if let id = file.id {
                    return selectedForDeletion.contains(id)
                }
                return false
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                // Global selection controls
                if !selectedForDeletion.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(selectedForDeletion.count) selected")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Button {
                            selectedForDeletion.removeAll()
                        } label: {
                            Text("Clear All")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            
            // Directory headers - side by side with minimal spacing
            HStack(spacing: 0) {
                // Left directory (Directory 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directory 1")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(pair.directory1)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    
                    HStack(spacing: 8) {
                        Button {
                            openDirectoryInFinder(pair.directory1)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Open in Finder")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.link)
                        
                        if !isLoadingFiles && !duplicatedFiles.isEmpty {
                            Button {
                                // Select all files from Directory 1
                                var dir1Ids: Set<Int64> = []
                                for filePair in duplicatedFiles {
                                    if let id1 = filePair.file1.id {
                                        dir1Ids.insert(id1)
                                    }
                                }
                                selectedForDeletion.formUnion(dir1Ids)
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Select All")
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            
                            let dir1SelectedCount = duplicatedFiles.filter { 
                                if let id = $0.file1.id { return selectedForDeletion.contains(id) }
                                return false
                            }.count
                            
                            if dir1SelectedCount > 0 {
                                Button {
                                    showingDeleteConfirmation = true
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "trash")
                                        Text("Delete (\(dir1SelectedCount))")
                                    }
                                    .font(.caption2)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                
                Divider()
                
                // Right directory (Directory 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directory 2")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(pair.directory2)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    
                    HStack(spacing: 8) {
                        Button {
                            openDirectoryInFinder(pair.directory2)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Open in Finder")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.link)
                        
                        if !isLoadingFiles && !duplicatedFiles.isEmpty {
                            Button {
                                // Select all files from Directory 2
                                var dir2Ids: Set<Int64> = []
                                for filePair in duplicatedFiles {
                                    if let id2 = filePair.file2.id {
                                        dir2Ids.insert(id2)
                                    }
                                }
                                selectedForDeletion.formUnion(dir2Ids)
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Select All")
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            
                            let dir2SelectedCount = duplicatedFiles.filter { 
                                if let id = $0.file2.id { return selectedForDeletion.contains(id) }
                                return false
                            }.count
                            
                            if dir2SelectedCount > 0 {
                                Button {
                                    showingDeleteConfirmation = true
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "trash")
                                        Text("Delete (\(dir2SelectedCount))")
                                    }
                                    .font(.caption2)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }
            .fixedSize(horizontal: false, vertical: true)
            
            // Side-by-side file list - starts immediately
            if isLoadingFiles {
                VStack {
                    Spacer()
                    ProgressView("Loading duplicated files...")
                        .progressViewStyle(.linear)
                        .padding()
                    if let error = loadError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(duplicatedFiles.enumerated()), id: \.offset) { index, pair in
                            SideBySideFileRow(
                                file1: pair.file1,
                                file2: pair.file2,
                                selectedForDeletion: $selectedForDeletion,
                                selectedPhoto: $selectedPhoto
                            )
                            .environmentObject(photoLibrary)
                            
                            if index < duplicatedFiles.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete \(selectedFiles.count) Files", isPresented: $showingDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) {
                let filesToDelete = selectedFiles  // Capture the files
                let deletedIds = Set(filesToDelete.compactMap { $0.id })
                print("🗑️ Starting deletion of \(filesToDelete.count) files")
                selectedForDeletion.removeAll()
                
                // Delete files asynchronously to avoid blocking UI
                Task {
                    // Delete all files
                    for file in filesToDelete {
                        photoLibrary.movePhotoToTrash(file)
                    }
                    
                    // Refresh duplicates ONCE after all deletions
                    print("🔄 Refreshing duplicate groups after batch deletion")
                    await MainActor.run {
                        photoLibrary.loadDuplicates()
                    }
                    
                    // Filter out deleted files from current list - much faster than full rescan
                    print("🔄 Filtering deleted files from list")
                    await MainActor.run {
                        // Remove pairs where either file was deleted
                        duplicatedFiles = duplicatedFiles.filter { pair in
                            let file1NotDeleted = !deletedIds.contains(pair.file1.id ?? -1)
                            let file2NotDeleted = !deletedIds.contains(pair.file2.id ?? -1)
                            return file1NotDeleted && file2NotDeleted
                        }
                        print("✅ Updated file list, now showing \(duplicatedFiles.count) pairs")
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let totalSize = selectedFiles.reduce(0) { $0 + $1.fileSize }
            Text("Move \(selectedFiles.count) files (\(ByteCountFormatter().string(fromByteCount: totalSize))) to the Trash?\n\nYou can restore them from Trash if needed.")
        }
        .onAppear {
            print("🔵 DirectoryComparisonDetailView appeared")
            print("   Directory 1: \(pair.directory1)")
            print("   Directory 2: \(pair.directory2)")
            
            // Cancel any existing task first
            loadTask?.cancel()
            
            // Load files asynchronously ONCE
            loadTask = Task {
                await loadDuplicatedFiles()
            }
        }
        .onDisappear {
            // Capture task reference and cancel asynchronously to avoid accessing
            // potentially deallocated state
            let taskToCancel = loadTask
            print("🔴 DirectoryComparisonDetailView disappearing - cancelling load task")
            
            // Cancel on next run loop to ensure we're not in the middle of state updates
            DispatchQueue.main.async {
                taskToCancel?.cancel()
            }
        }
    }
    
    private func getDirectoryPath(for photo: PhotoFile) -> String? {
        return photo.getAbsoluteDirectoryPath(rootDirectories: photoLibrary.rootDirectories)
    }
    
    private func openDirectoryInFinder(_ directoryPath: String) {
        print("📂 Opening directory in Finder: \(directoryPath)")
        
        // Find which root directory contains this path
        guard let rootDir = photoLibrary.rootDirectories.first(where: { directoryPath.hasPrefix($0.path) }) else {
            print("❌ No root directory found for path: \(directoryPath)")
            return
        }
        
        // Start accessing security-scoped resource if bookmark data exists
        var securityScopedURL: URL?
        if let bookmarkData = rootDir.bookmarkData {
            do {
                var isStale = false
                securityScopedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if let url = securityScopedURL {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    print("🔓 Started security-scoped access: \(didStartAccessing)")
                }
            } catch {
                print("⚠️ Failed to resolve bookmark: \(error.localizedDescription)")
            }
        }
        
        // Ensure we stop accessing the resource when done
        defer {
            if let url = securityScopedURL {
                url.stopAccessingSecurityScopedResource()
                print("🔒 Stopped security-scoped access")
            }
        }
        
        // Open the directory
        if FileManager.default.fileExists(atPath: directoryPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: directoryPath))
            print("✅ Opened directory in Finder")
        } else {
            print("❌ Directory does not exist: \(directoryPath)")
        }
    }
    
    private func loadDuplicatedFiles() async {
        let startTime = Date()
        print("⏱️ Starting to load duplicated files between:")
        print("   Directory 1: \(pair.directory1)")
        print("   Directory 2: \(pair.directory2)")
        print("   Total duplicate groups to scan: \(photoLibrary.duplicateGroups.count)")
        
        var pairs: [(PhotoFile, PhotoFile)] = []
        var processedGroups = 0
        
        // Process groups in background
        for group in photoLibrary.duplicateGroups where group.files.count > 1 {
            // Check if task was cancelled
            if Task.isCancelled {
                print("⚠️ Load task cancelled after processing \(processedGroups) groups")
                return
            }
            
            processedGroups += 1
            
            // Progress logging every 500 groups
            if processedGroups % 500 == 0 {
                print("📄 Processed \(processedGroups)/\(photoLibrary.duplicateGroups.count) groups, found \(pairs.count) file pairs so far...")
            }
            
            // ONLY include files with valid absolute paths
            let filesInDir1 = group.files.filter { 
                guard let dirPath = getDirectoryPath(for: $0) else { return false }
                return dirPath == pair.directory1
            }
            let filesInDir2 = group.files.filter { 
                guard let dirPath = getDirectoryPath(for: $0) else { return false }
                return dirPath == pair.directory2
            }
            
            // All files in filesInDir1 are duplicates of all files in filesInDir2 (same hash)
            for file1 in filesInDir1 {
                for file2 in filesInDir2 {
                    pairs.append((file1, file2))
                }
            }
        }
        
        // Check again before updating UI
        if Task.isCancelled {
            print("⚠️ Load task cancelled before updating UI")
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ Finished loading \(pairs.count) duplicated file pairs in \(String(format: "%.2f", elapsed))s")
        
        // Sort by filename on background thread
        let sortedPairs = pairs.sorted(by: { $0.0.fileName < $1.0.fileName })
        
        // Update UI on main thread - only if not cancelled
        if !Task.isCancelled {
            await MainActor.run {
                self.duplicatedFiles = sortedPairs
                self.isLoadingFiles = false
                print("   Duplicated files count: \(duplicatedFiles.count)")
            }
        } else {
            print("⚠️ Load task cancelled, skipping UI update")
        }
    }
}

struct SideBySideFileRow: View {
    let file1: PhotoFile
    let file2: PhotoFile
    @Binding var selectedForDeletion: Set<Int64>
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    // Verify hashes match
    private var hashesMatch: Bool {
        file1.fileHash == file2.fileHash
    }
    
    private var file1Selected: Bool {
        if let id = file1.id {
            return selectedForDeletion.contains(id)
        }
        return false
    }
    
    private var file2Selected: Bool {
        if let id = file2.id {
            return selectedForDeletion.contains(id)
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Hash match indicator
            if !hashesMatch {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Warning: Hashes don't match! file1: \(String(file1.fileHash.prefix(8))) vs file2: \(String(file2.fileHash.prefix(8)))")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(4)
                .background(Color.red.opacity(0.1))
            }
            
            HStack(spacing: 0) {
                // Left file (from directory 1)
                FileCell(
                file: file1,
                isSelected: file1Selected,
                selectedPhoto: $selectedPhoto,
                backgroundColor: Color.blue.opacity(0.05),
                onToggleSelection: {
                    if let id = file1.id {
                        if selectedForDeletion.contains(id) {
                            selectedForDeletion.remove(id)
                        } else {
                            selectedForDeletion.insert(id)
                        }
                    }
                }
            )
            .environmentObject(photoLibrary)
            
            Divider()
            
            // Right file (from directory 2)
            FileCell(
                file: file2,
                isSelected: file2Selected,
                selectedPhoto: $selectedPhoto,
                backgroundColor: Color.orange.opacity(0.05),
                onToggleSelection: {
                    if let id = file2.id {
                        if selectedForDeletion.contains(id) {
                            selectedForDeletion.remove(id)
                        } else {
                            selectedForDeletion.insert(id)
                        }
                    }
                }
            )
            .environmentObject(photoLibrary)
            }
        }
    }
}

struct FileCell: View {
    let file: PhotoFile
    let isSelected: Bool
    @Binding var selectedPhoto: PhotoFile?
    let backgroundColor: Color
    let onToggleSelection: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    private var fullPath: String {
        if let absolutePath = file.getAbsoluteFullPath(rootDirectories: photoLibrary.rootDirectories) {
            return absolutePath
        }
        // If we can't get absolute path, return error message
        return "[ERROR: Missing root directory for file: \(file.fileName)]"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button {
                onToggleSelection()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .buttonStyle(.plain)
            
            // Thumbnail
            ReusableHoverThumbnail(photo: file, size: 50, onTap: {
                selectedPhoto = file
            })
            .frame(width: 50, height: 50)
            .environmentObject(photoLibrary)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                // Show full path
                Text(fullPath)
                    .font(.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
                
                HStack(spacing: 8) {
                    Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let dateTaken = file.exifDateTaken {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(dateTaken, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(String(file.fileHash.prefix(8)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.2) : backgroundColor)
    }
}
