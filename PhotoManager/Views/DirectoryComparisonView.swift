import SwiftUI

struct DirectoryComparisonView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var selectedComparison: DirectoryPair?
    @State private var isLoading = false
    @State private var loadedPairs: [DirectoryPair] = []
    /// Bumped when the duplicate groups or roots change; the pair list is recomputed only then.
    @State private var sourceVersion = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading || photoLibrary.isLoadingDuplicates {
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
                
                if isLoading || photoLibrary.isLoadingDuplicates {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            if selectedComparison == nil {
                // List of directory pairs
                if isLoading && loadedPairs.isEmpty {
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
        .task(id: sourceVersion) { await loadDirectoryPairs() }
        .onReceive(photoLibrary.$duplicateGroups.dropFirst()) { _ in sourceVersion += 1 }
        .onReceive(photoLibrary.$rootDirectories.dropFirst()) { _ in sourceVersion += 1 }
    }
    
    private func loadDirectoryPairs() async {
        isLoading = true
        let groups = photoLibrary.duplicateGroups
        let rootPaths = Self.rootPathMap(photoLibrary.rootDirectories)
        let work = Task.detached(priority: .userInitiated) {
            Self.calculateDirectoryPairs(groups: groups, rootPaths: rootPaths)
        }
        let pairs = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled, let pairs else { return }  // a newer load replaces this one
        loadedPairs = pairs
        isLoading = false
    }

    nonisolated static func rootPathMap(_ roots: [RootDirectory]) -> [Int64: String] {
        Dictionary(roots.compactMap { r in r.id.map { ($0, r.path) } }, uniquingKeysWith: { a, _ in a })
    }

    nonisolated static func absoluteDirectory(of file: PhotoFile, rootPaths: [Int64: String]) -> String? {
        guard let root = rootPaths[file.rootDirectoryId] else { return nil }
        return (root as NSString).appendingPathComponent(file.directoryPath)
    }

    /// Counts directory pairs from an inverted index (content hash → directories holding it), so the
    /// cost is proportional to the duplicate files, not to the square of the number of directories.
    /// Returns nil if cancelled.
    nonisolated static func calculateDirectoryPairs(groups: [DuplicateGroup], rootPaths: [Int64: String]) -> [DirectoryPair]? {
        struct PairKey: Hashable { let a: String; let b: String }
        var pairStats: [PairKey: (count: Int, wasted: Int64)] = [:]

        for (index, group) in groups.enumerated() where group.files.count > 1 {
            if index % 256 == 0 && Task.isCancelled { return nil }
            var perDirectory: [String: Int] = [:]
            for file in group.files {
                if let dir = absoluteDirectory(of: file, rootPaths: rootPaths) {
                    perDirectory[dir, default: 0] += 1
                }
            }
            guard perDirectory.count > 1 else { continue }
            let dirs = perDirectory.keys.sorted()
            let fileSize = group.files.first?.fileSize ?? 0
            for i in 0..<dirs.count {
                for j in (i + 1)..<dirs.count {
                    let total = perDirectory[dirs[i]]! + perDirectory[dirs[j]]!
                    let key = PairKey(a: dirs[i], b: dirs[j])
                    var stats = pairStats[key] ?? (0, 0)
                    stats.count += total
                    stats.wasted += fileSize * Int64(total - 1)
                    pairStats[key] = stats
                }
            }
        }
        if Task.isCancelled { return nil }

        return pairStats.map { key, stats in
            DirectoryPair(directory1: key.a, directory2: key.b,
                          sharedDuplicateCount: stats.count, wastedSpace: stats.wasted)
        }.sorted { $0.sharedDuplicateCount > $1.sharedDuplicateCount }
    }
    
    private func openComparisonWindow(for pair: DirectoryPair) {
        // Create new window - each window is independent
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Compare: \(pair.directory1.split(separator: "/").last ?? "") vs \(pair.directory2.split(separator: "/").last ?? "")"
        window.center()
        window.isReleasedWhenClosed = false  // the window controller owns it
        
        // Create a window controller to keep the window alive
        let windowController = NSWindowController(window: window)
        
        // Create comparison view
        let comparisonView = DirectoryComparisonDetailView(
            pair: pair,
            selectedPhoto: $selectedPhoto,
            windowController: windowController,
            onBack: { [weak window] in
                window?.close()
            }
        )
        .environmentObject(photoLibrary)
        
        window.contentView = NSHostingView(rootView: comparisonView)
        windowController.showWindow(nil)
        
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
                    Text(DuplicateFormat.size(pair.wastedSpace))
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
    @State private var pendingDeletion: [PhotoFile] = []
    @State private var pendingSideName = ""
    @State private var trashResultMessage: String?
    @State private var showingPairHint = false
    @State private var duplicatedFiles: [(file1: PhotoFile, file2: PhotoFile)] = []
    /// For each file id, the ids it is paired with on the other side.
    @State private var partners: [Int64: Set<Int64>] = [:]
    @State private var isLoadingFiles = true
    @State private var loadError: String?
    @State private var loadVersion = 0

    private func isSelected(_ file: PhotoFile) -> Bool {
        file.id.map { selectedForDeletion.contains($0) } ?? false
    }

    /// A file may be selected only if none of its pair partners is: one copy of each pair is always kept.
    private func canSelect(_ file: PhotoFile) -> Bool {
        guard let id = file.id else { return false }
        return partners[id, default: []].isDisjoint(with: selectedForDeletion)
    }

    private func toggle(_ file: PhotoFile) {
        guard let id = file.id else { return }
        if selectedForDeletion.contains(id) {
            selectedForDeletion.remove(id)
        } else if canSelect(file) {
            selectedForDeletion.insert(id)
        } else {
            flashPairHint()
        }
    }

    private func selectAll(side1: Bool) {
        var skipped = false
        for filePair in duplicatedFiles {
            let file = side1 ? filePair.file1 : filePair.file2
            guard let id = file.id, !selectedForDeletion.contains(id) else { continue }
            if canSelect(file) { selectedForDeletion.insert(id) } else { skipped = true }
        }
        if skipped { flashPairHint() }
    }

    /// Unique selected files on one side.
    private func selectedFiles(side1: Bool) -> [PhotoFile] {
        var seen: Set<Int64> = []
        return duplicatedFiles.compactMap { filePair in
            let file = side1 ? filePair.file1 : filePair.file2
            guard let id = file.id, selectedForDeletion.contains(id), seen.insert(id).inserted else { return nil }
            return file
        }
    }

    private func flashPairHint() {
        showingPairHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showingPairHint = false }
    }

    private func confirmDelete(side1: Bool) {
        pendingDeletion = selectedFiles(side1: side1)
        pendingSideName = side1 ? "Directory 1" : "Directory 2"
        showingDeleteConfirmation = !pendingDeletion.isEmpty
    }

    private func deletePending() {
        let files = pendingDeletion
        pendingDeletion = []
        guard !files.isEmpty else { return }
        let result = photoLibrary.trashPhotos(files)  // guarded, refreshes the duplicate lists itself
        let removed = Set(result.trashed.compactMap(\.id))
        selectedForDeletion.subtract(files.compactMap(\.id))
        // Drop pairs that lost a file right away; the full reload follows when the duplicate lists refresh.
        duplicatedFiles.removeAll { removed.contains($0.file1.id ?? -1) || removed.contains($0.file2.id ?? -1) }
        trashResultMessage = result.summary + "."
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

                if showingPairHint {
                    Label("One file of each pair is always kept", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
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
                directoryHeader(title: "Directory 1", path: pair.directory1, side1: true)
                    .background(Color.blue.opacity(0.1))
                
                Divider()
                
                directoryHeader(title: "Directory 2", path: pair.directory2, side1: false)
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
                        ForEach(Array(duplicatedFiles.enumerated()), id: \.offset) { index, filePair in
                            SideBySideFileRow(
                                file1: filePair.file1,
                                file2: filePair.file2,
                                selectedForDeletion: $selectedForDeletion,
                                selectedPhoto: $selectedPhoto,
                                onToggle: { toggle($0) }
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
        .alert("Delete \(pendingDeletion.count) Files from \(pendingSideName)", isPresented: $showingDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) { deletePending() }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            let totalSize = pendingDeletion.reduce(0) { $0 + $1.fileSize }
            Text("Move \(pendingDeletion.count) files (\(DuplicateFormat.size(totalSize))) from \(pendingSideName) to the Trash?\n\nOne copy of every photo is always kept. You can restore files from the Trash if needed.")
        }
        .alert("Directory Comparison", isPresented: Binding(get: { trashResultMessage != nil }, set: { if !$0 { trashResultMessage = nil } })) {
            Button("OK", role: .cancel) { trashResultMessage = nil }
        } message: {
            Text(trashResultMessage ?? "")
        }
        .task(id: loadVersion) { await loadDuplicatedFiles() }
        .onReceive(photoLibrary.$duplicateGroups.dropFirst()) { _ in loadVersion += 1 }
    }

    @ViewBuilder
    private func directoryHeader(title: String, path: String, side1: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(path)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
            
            HStack(spacing: 8) {
                Button {
                    openDirectoryInFinder(path)
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
                        selectAll(side1: side1)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle")
                            Text("Select All")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .help("Selects every file on this side whose partner on the other side is not selected")
                    
                    let selectedCount = selectedFiles(side1: side1).count
                    if selectedCount > 0 {
                        Button {
                            confirmDelete(side1: side1)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "trash")
                                Text("Delete (\(selectedCount))")
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
    }
    
    private func openDirectoryInFinder(_ directoryPath: String) {
        // Find which root directory contains this path
        guard let rootDir = photoLibrary.rootDirectories.first(where: { directoryPath.hasPrefix($0.path) }) else {
            return
        }
        SecurityScope.withAccess(rootDir) {
            if FileManager.default.fileExists(atPath: directoryPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: directoryPath))
            }
        }
    }
    
    /// Finds the file pairs shared by the two directories off the main thread.
    private func loadDuplicatedFiles() async {
        let groups = photoLibrary.duplicateGroups
        let rootPaths = DirectoryComparisonView.rootPathMap(photoLibrary.rootDirectories)
        let dir1 = pair.directory1
        let dir2 = pair.directory2
        let work = Task.detached(priority: .userInitiated) { () -> [(file1: PhotoFile, file2: PhotoFile)]? in
            var pairs: [(file1: PhotoFile, file2: PhotoFile)] = []
            for (index, group) in groups.enumerated() where group.files.count > 1 {
                if index % 256 == 0 && Task.isCancelled { return nil }
                var filesInDir1: [PhotoFile] = []
                var filesInDir2: [PhotoFile] = []
                for file in group.files {
                    let dir = DirectoryComparisonView.absoluteDirectory(of: file, rootPaths: rootPaths)
                    if dir == dir1 { filesInDir1.append(file) } else if dir == dir2 { filesInDir2.append(file) }
                }
                // All files in filesInDir1 are duplicates of all files in filesInDir2 (same hash)
                for file1 in filesInDir1 {
                    for file2 in filesInDir2 {
                        pairs.append((file1, file2))
                    }
                }
            }
            return pairs.sorted { $0.file1.fileName < $1.file1.fileName }
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled, let result else { return }

        var partnerMap: [Int64: Set<Int64>] = [:]
        for filePair in result {
            guard let a = filePair.file1.id, let b = filePair.file2.id else { continue }
            partnerMap[a, default: []].insert(b)
            partnerMap[b, default: []].insert(a)
        }
        duplicatedFiles = result
        partners = partnerMap
        selectedForDeletion.formIntersection(partnerMap.keys)
        isLoadingFiles = false
    }
}

struct SideBySideFileRow: View {
    let file1: PhotoFile
    let file2: PhotoFile
    @Binding var selectedForDeletion: Set<Int64>
    @Binding var selectedPhoto: PhotoFile?
    /// Toggles a file's selection; the parent refuses to select both files of a pair.
    let onToggle: (PhotoFile) -> Void
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
                onToggleSelection: { onToggle(file1) }
            )
            .environmentObject(photoLibrary)
            
            Divider()
            
            // Right file (from directory 2)
            FileCell(
                file: file2,
                isSelected: file2Selected,
                selectedPhoto: $selectedPhoto,
                backgroundColor: Color.orange.opacity(0.05),
                onToggleSelection: { onToggle(file2) }
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
                    Text(DuplicateFormat.size(file.fileSize))
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
