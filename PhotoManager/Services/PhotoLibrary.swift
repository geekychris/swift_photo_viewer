import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "photolibrary")

/// Result of a guarded trash operation.
struct TrashResult {
    var trashed: [PhotoFile] = []
    /// Kept because trashing them would have removed the last copy of that content.
    var keptLastCopy: [PhotoFile] = []
    var failed: [(PhotoFile, String)] = []

    var summary: String {
        var parts = ["Moved \(trashed.count) file\(trashed.count == 1 ? "" : "s") to the Trash"]
        if !keptLastCopy.isEmpty { parts.append("kept \(keptLastCopy.count) that had no other copy") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }
}

class PhotoLibrary: ObservableObject {
    let databaseManager: DatabaseManager
    private let fileScanningService: FileScanningService
    private let thumbnailService: ThumbnailService

    @Published var rootDirectories: [RootDirectory] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var directoryDuplicates: [DirectoryDuplicateInfo] = []
    @Published var completeDuplicateDirectories: [CompleteDuplicateDirectory] = []
    @Published var isLoading = false
    @Published var isLoadingDuplicates = false
    @Published var scanStatus: String = ""
    @Published var scanProgress: Double = 0
    @Published var errorMessage: String?
    @Published var thumbnailsUpdated = Date() // Triggers UI refresh when thumbnails are generated
    /// Bumped whenever catalogue contents change (scan, trash, move, assignment); views reload on it.
    @Published var libraryVersion = 0

    private var duplicatesTask: Task<Void, Never>?
    private var thumbnailObserver: NSObjectProtocol?

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
        self.fileScanningService = FileScanningService(databaseManager: databaseManager)
        self.thumbnailService = ThumbnailService(databaseManager: databaseManager)
        loadRootDirectories()
        loadDuplicates()

        thumbnailObserver = NotificationCenter.default.addObserver(forName: .thumbnailsUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.thumbnailsUpdated = Date()
        }
    }

    deinit {
        if let thumbnailObserver { NotificationCenter.default.removeObserver(thumbnailObserver) }
    }

    /// Marks the catalogue as changed so views reload, and refreshes duplicate lists in the background.
    func libraryDidChange(refreshDuplicates: Bool = true) {
        let apply = { [self] in
            libraryVersion += 1
            if refreshDuplicates { loadDuplicates() }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    func loadRootDirectories() {
        do {
            rootDirectories = try databaseManager.getRootDirectories()
        } catch {
            errorMessage = "Failed to load directories: \(error.localizedDescription)"
        }
    }

    func rootDirectory(id: Int64) -> RootDirectory? {
        rootDirectories.first { $0.id == id }
    }

    func addRootDirectory(path: String, name: String, bookmarkData: Data?) {
        do {
            let directory = RootDirectory(path: path, name: name, bookmarkData: bookmarkData)
            let newDirectoryId = try databaseManager.addRootDirectory(directory)
            loadRootDirectories()
            if let newDirectory = rootDirectories.first(where: { $0.id == newDirectoryId }) {
                Task { await scanDirectory(newDirectory) }
            }
        } catch {
            errorMessage = "Failed to add directory: \(error.localizedDescription)"
        }
    }

    /// - Parameter fastScan: kept for the existing buttons. Fast skips unchanged files; otherwise every
    ///   file is re-read. Neither discards ratings, tags or events.
    func scanDirectory(_ directory: RootDirectory, fastScan: Bool = false, regenerateThumbnails: Bool = false) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            scanStatus = "Scanning \(directory.name)…"
            scanProgress = 0
        }

        do {
            let summary = try await fileScanningService.scanDirectory(directory, fullRescan: !fastScan) { [weak self] p in
                Task { @MainActor in
                    self?.scanProgress = p.fraction
                    self?.scanStatus = p.total > 0 ? "\(p.phase) \(p.completed)/\(p.total)" : p.phase
                }
            }
            libraryDidChange(refreshDuplicates: false)
            await MainActor.run { scanStatus = "Generating thumbnails…" }
            try await thumbnailService.generateThumbnailsForDirectory(directory, regenerateAll: regenerateThumbnails) { [weak self] done, total in
                Task { @MainActor in
                    self?.scanProgress = total > 0 ? Double(done) / Double(total) : 1
                    self?.scanStatus = "Thumbnails \(done)/\(total)"
                }
            }
            await MainActor.run {
                loadRootDirectories()
                isLoading = false
                scanStatus = "\(directory.name): \(summary.found) files, \(summary.added) new, \(summary.updated) changed, \(summary.removed) removed"
                libraryDidChange()
            }
        } catch {
            logger.error("Failed to scan directory: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                errorMessage = "Failed to scan directory: \(error.localizedDescription)"
                isLoading = false
                scanStatus = ""
            }
        }
    }

    func getPhotosForDirectory(_ directoryId: Int64) -> [PhotoFile] {
        do {
            return try databaseManager.getPhotosForDirectory(directoryId)
        } catch {
            errorMessage = "Failed to load photos: \(error.localizedDescription)"
            return []
        }
    }

    /// Recomputes the duplicate lists off the main thread. Overlapping requests collapse into the latest.
    func loadDuplicates() {
        duplicatesTask?.cancel()
        isLoadingDuplicates = true
        let db = databaseManager
        duplicatesTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let groups = try db.findDuplicates()
                try Task.checkCancellation()
                let byDirectory = try db.findDuplicatesByDirectory(groups: groups)
                try Task.checkCancellation()
                let complete = try db.findCompleteDuplicateDirectories()
                try Task.checkCancellation()
                await MainActor.run {
                    self?.duplicateGroups = groups
                    self?.directoryDuplicates = byDirectory
                    self?.completeDuplicateDirectories = complete
                    self?.isLoadingDuplicates = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to load duplicates: \(error.localizedDescription)"
                    self?.isLoadingDuplicates = false
                }
            }
        }
    }

    func getThumbnailImage(for photo: PhotoFile) -> NSImage? {
        thumbnailService.getThumbnailImage(for: photo)
    }

    func absolutePath(for photo: PhotoFile) -> String? {
        photo.getAbsoluteFullPath(rootDirectories: rootDirectories)
    }

    // MARK: - Guarded trash

    /// Moves files to the Trash and removes them from the catalogue, never removing the last remaining
    /// copy of any content unless `allowLastCopy` is set (the caller must have asked the user).
    @discardableResult
    func trashPhotos(_ photos: [PhotoFile], allowLastCopy: Bool = false) -> TrashResult {
        var result = TrashResult()
        let deleting = Set(photos.compactMap(\.id))
        var toTrash: [PhotoFile] = []

        // Group by content so "keep one" is decided per photo, not per file.
        for (hash, files) in Dictionary(grouping: photos, by: \.fileHash) {
            let survivors = (try? databaseManager.copyCount(hash: hash, excluding: deleting)) ?? 0
            if survivors == 0 && !allowLastCopy {
                // Keep the first (by path) so the choice is stable.
                let sorted = files.sorted { $0.relativePath < $1.relativePath }
                result.keptLastCopy.append(sorted[0])
                toTrash.append(contentsOf: sorted.dropFirst())
            } else {
                toTrash.append(contentsOf: files)
            }
        }

        var removedIds: [Int64] = []
        for (rootId, files) in Dictionary(grouping: toTrash, by: \.rootDirectoryId) {
            guard let root = rootDirectory(id: rootId) else {
                result.failed.append(contentsOf: files.map { ($0, "Library root not found") })
                continue
            }
            SecurityScope.withAccess(root) {
                for file in files {
                    let path = (root.path as NSString).appendingPathComponent(file.relativePath)
                    do {
                        if FileManager.default.fileExists(atPath: path) {
                            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                        }
                        if let id = file.id { removedIds.append(id) }
                        result.trashed.append(file)
                    } catch {
                        result.failed.append((file, error.localizedDescription))
                    }
                }
            }
        }

        do {
            let orphaned = try databaseManager.deletePhotos(ids: removedIds)
            ThumbnailService.deleteThumbnails(forHashes: orphaned)
        } catch {
            errorMessage = "Trashed files but could not update the catalogue: \(error.localizedDescription)"
        }
        if !result.failed.isEmpty {
            errorMessage = result.summary + ". First error: \(result.failed[0].1)"
        }
        libraryDidChange()
        return result
    }

    func movePhotoToTrash(_ photo: PhotoFile) {
        trashPhotos([photo])
    }

    func deletePhoto(_ photoId: Int64) {
        do {
            try databaseManager.deletePhoto(photoId)
            libraryDidChange()
        } catch {
            errorMessage = "Failed to delete photo: \(error.localizedDescription)"
        }
    }

    /// Trashes this directory's duplicated files, keeping one copy of anything not stored elsewhere.
    func deleteAllDuplicatesInDirectory(_ dirInfo: DirectoryDuplicateInfo) {
        trashPhotos(dirInfo.files)
    }

    func deleteRootDirectory(_ directory: RootDirectory) {
        guard let directoryId = directory.id else {
            errorMessage = "Cannot delete directory: No ID found"
            return
        }
        do {
            let hashes = Set(getPhotosForDirectory(directoryId).map(\.fileHash))
            try databaseManager.deleteRootDirectory(directoryId)
            let orphaned = hashes.filter { ((try? databaseManager.copyCount(hash: $0)) ?? 1) == 0 }
            ThumbnailService.deleteThumbnails(forHashes: Array(orphaned))
            loadRootDirectories()
            libraryDidChange()
        } catch {
            errorMessage = "Failed to delete directory: \(error.localizedDescription)"
        }
    }

    // MARK: - Timeline (aggregated in SQL)

    struct TimelinePeriod: Identifiable, Hashable {
        var id: String { key }
        let key: String        // "2019", "2019-03", "2019-03-12" or "2019-W10"
        let count: Int
    }

    func timeline(_ dimension: PivotDimension, filter: PhotoFilter = .all) -> [(year: String, periods: [TimelinePeriod])] {
        let rows = (try? databaseManager.pivot(dimension, filter: filter)) ?? []
        let grouped = Dictionary(grouping: rows) { String($0.key.prefix(4)) }
        return grouped.map { year, rows in
            (year, rows.map { TimelinePeriod(key: $0.key, count: $0.count) }.sorted { $0.key > $1.key })
        }
        .sorted { $0.year > $1.year }
    }

    // MARK: - Metadata

    func updatePhotoMetadata(_ photoId: Int64, description: String?, tags: String?) {
        do {
            try databaseManager.updatePhotoMetadata(photoId, description: description, tags: tags)
            libraryDidChange(refreshDuplicates: false)
        } catch {
            errorMessage = "Failed to update photo metadata: \(error.localizedDescription)"
        }
    }

    func updatePhotoRating(_ photoId: Int64, rating: Int) {
        do {
            try databaseManager.updatePhotoRating(photoId, rating: rating)
            libraryDidChange(refreshDuplicates: false)
        } catch {
            errorMessage = "Failed to update photo rating: \(error.localizedDescription)"
        }
    }

    func updatePhotoColorTag(_ photoId: Int64, colorTag: String?) {
        do {
            try databaseManager.updatePhotoColorTag(photoId, colorTag: colorTag)
            libraryDidChange(refreshDuplicates: false)
        } catch {
            errorMessage = "Failed to update photo color tag: \(error.localizedDescription)"
        }
    }

    func getPhotoById(_ photoId: Int64) -> PhotoFile? {
        try? databaseManager.getPhotoById(photoId)
    }

    func searchPhotos(query: String, minRating: Int? = nil, colorTag: String? = nil) -> [PhotoFile] {
        do {
            return try databaseManager.searchPhotos(query: query, minRating: minRating, colorTag: colorTag)
        } catch {
            errorMessage = "Failed to search photos: \(error.localizedDescription)"
            return []
        }
    }

    func getPhotosByRating(minRating: Int) -> [PhotoFile] {
        (try? databaseManager.getPhotosByRating(minRating: minRating)) ?? []
    }

    func getPhotosByColorTag(_ colorTag: String) -> [PhotoFile] {
        (try? databaseManager.getPhotosByColorTag(colorTag)) ?? []
    }

    // MARK: - CSV export

    func exportDuplicatesToCSV(includeDirectoryView: Bool = false) -> URL? {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "duplicates_export_\(dateFormatter.string(from: Date())).csv"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsPath.appendingPathComponent(filename)
            let bytes = ByteCountFormatter()

            var csv = ""
            if includeDirectoryView {
                csv += "Directory Path,Total Files,Duplicate Files,Duplicate %,Total Size,Wasted Size\n"
                for d in directoryDuplicates {
                    csv += "\(q(d.fullPath)),\(d.fileCount),\(d.duplicateFileCount),\(String(format: "%.1f", d.duplicatePercentage))%,\(bytes.string(fromByteCount: d.totalSize)),\(bytes.string(fromByteCount: d.wastedSize))\n"
                }
                csv += "\n\nComplete Duplicate Directories\nPrimary Directory,Duplicate Directories,File Count,Total Size\n"
                for c in completeDuplicateDirectories {
                    csv += "\(q(c.primaryDirectory.fullPath)),\(q(c.duplicateDirectories.map(\.fullPath).joined(separator: "; "))),\(c.fileCount),\(bytes.string(fromByteCount: c.totalSize))\n"
                }
            } else {
                csv += "File Hash,Duplicate Count,Total Size,File Name,Locations\n"
                for group in duplicateGroups {
                    let paths = group.files.compactMap(absolutePath(for:))
                    guard !paths.isEmpty else { continue }
                    csv += "\(q(group.fileHash)),\(paths.count),\(bytes.string(fromByteCount: group.totalSize)),\(q(group.files[0].fileName)),\(q(paths.joined(separator: "; ")))\n"
                }
            }
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            errorMessage = "Failed to export CSV: \(error.localizedDescription)"
            return nil
        }
    }

    /// Trashes the listed files of a duplicate directory (never the folder itself, which may hold
    /// subfolders or other files), keeping one copy of anything not stored elsewhere.
    func moveDirectoryToTrash(_ directoryInfo: DirectoryInfo) {
        trashPhotos(directoryInfo.files)
    }
}
