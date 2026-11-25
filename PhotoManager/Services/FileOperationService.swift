import Foundation
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "fileops")

// MARK: - Destination Type

enum Destination: Equatable {
    case managedDirectory(RootDirectory)
    case unmanagedURL(URL) // Keeps the security-scoped URL from the folder picker

    static func ==(lhs: Destination, rhs: Destination) -> Bool {
        switch (lhs, rhs) {
        case (.managedDirectory(let a), .managedDirectory(let b)):
            return a.id == b.id
        case (.unmanagedURL(let a), .unmanagedURL(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum FileOperationKind {
    case copy
    case move
}

struct FileOperationResult {
    var kind: FileOperationKind
    var succeeded: [PhotoFile] = []
    var skipped: [(PhotoFile, String)] = []
    var failed: [(PhotoFile, String)] = []
    /// Files that were moved but whose catalogue row could not be updated.
    var catalogueErrors: [(PhotoFile, String)] = []

    var summary: String {
        let verb = kind == .copy ? "Copied" : "Moved"
        var parts = ["\(verb) \(succeeded.count) file\(succeeded.count == 1 ? "" : "s")"]
        if !skipped.isEmpty { parts.append("skipped \(skipped.count) already in the destination") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        var text = parts.joined(separator: ", ")
        if let first = failed.first {
            text += ".\nFirst error: \(first.0.fileName): \(first.1)"
        }
        if !catalogueErrors.isEmpty {
            text += "\n\(catalogueErrors.count) moved file\(catalogueErrors.count == 1 ? "" : "s") could not be updated in the catalogue; rescan the library."
        }
        return text
    }
}

/// Copies and moves catalogued files without ever overwriting or deleting an existing file.
///
/// - A file whose source and destination are the same path is skipped.
/// - Name collisions get " (2)", " (3)"… suffixes.
/// - A move into a managed root relocates the catalogue row; a move out of the library removes it.
/// - Copies into a managed root are picked up by the next scan.
final class FileOperationService {
    private let databaseManager: DatabaseManager
    private let fileManager = FileManager.default

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// Runs the operation. Call off the main thread; `roots` is a snapshot of the library's roots.
    func perform(_ kind: FileOperationKind, photos: [PhotoFile], to destination: Destination, roots: [RootDirectory]) async -> FileOperationResult {
        var result = FileOperationResult(kind: kind)

        // Resolve where files go, and whether that place is inside a managed root.
        let destDir: String
        var unmanagedURL: URL?
        switch destination {
        case .managedDirectory(let root):
            destDir = root.path
        case .unmanagedURL(let url):
            destDir = url.path
            unmanagedURL = url
        }
        let destTarget = Self.managedLocation(for: destDir, roots: roots)

        // Keep access to the picked folder for the whole operation.
        let accessingUnmanaged = unmanagedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessingUnmanaged { unmanagedURL?.stopAccessingSecurityScopedResource() } }

        let sourceRootIds = Set(photos.map(\.rootDirectoryId))
        var scopedRoots = roots.filter { root in root.id.map(sourceRootIds.contains) ?? false }
        if let target = destTarget, !scopedRoots.contains(where: { $0.id == target.root.id }) {
            scopedRoots.append(target.root)
        }

        var leftLibrary: [Int64] = []
        await SecurityScope.withAccess(scopedRoots) { () async -> Void in
            for photo in photos {
                guard let root = roots.first(where: { $0.id == photo.rootDirectoryId }) else {
                    result.failed.append((photo, "Library root not found"))
                    continue
                }
                let sourcePath = (root.path as NSString).appendingPathComponent(photo.relativePath)
                guard fileManager.fileExists(atPath: sourcePath) else {
                    result.failed.append((photo, "Source file not found"))
                    continue
                }

                let directPath = (destDir as NSString).appendingPathComponent(photo.fileName)
                if Self.samePath(directPath, sourcePath) {
                    result.skipped.append((photo, "Already in the destination"))
                    continue
                }

                let finalPath = uniquePath(directPath)
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let destURL = URL(fileURLWithPath: finalPath)
                do {
                    switch kind {
                    case .copy: try fileManager.copyItem(at: sourceURL, to: destURL)
                    case .move: try fileManager.moveItem(at: sourceURL, to: destURL)
                    }
                } catch {
                    logger.error("\(kind == .copy ? "Copy" : "Move", privacy: .public) failed for \(sourcePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    result.failed.append((photo, error.localizedDescription))
                    continue
                }
                result.succeeded.append(photo)

                guard kind == .move, let photoId = photo.id else { continue }
                if let target = destTarget, let rootId = target.root.id {
                    let name = (finalPath as NSString).lastPathComponent
                    let relative = target.relativeDir.isEmpty ? name : (target.relativeDir as NSString).appendingPathComponent(name)
                    do {
                        try databaseManager.relocatePhoto(photoId, rootId: rootId, relativePath: relative)
                    } catch {
                        logger.error("Could not relocate row \(photoId): \(error.localizedDescription, privacy: .public)")
                        result.catalogueErrors.append((photo, error.localizedDescription))
                    }
                } else {
                    // The file now lives outside the library; it is no longer catalogued.
                    leftLibrary.append(photoId)
                }
            }
        }

        if !leftLibrary.isEmpty {
            do {
                let orphaned = try databaseManager.deletePhotos(ids: leftLibrary)
                ThumbnailService.deleteThumbnails(forHashes: orphaned)
            } catch {
                logger.error("Could not remove moved rows: \(error.localizedDescription, privacy: .public)")
                let moved = result.succeeded.filter { $0.id.map(leftLibrary.contains) ?? false }
                result.catalogueErrors.append(contentsOf: moved.map { ($0, error.localizedDescription) })
            }
        }
        return result
    }

    /// The managed root containing `path`, and the directory relative to it ("" for the root itself).
    static func managedLocation(for path: String, roots: [RootDirectory]) -> (root: RootDirectory, relativeDir: String)? {
        let target = normalized(path)
        // Most specific root first, in case roots are nested.
        for root in roots.sorted(by: { $0.path.count > $1.path.count }) {
            let rootPath = normalized(root.path)
            if target == rootPath { return (root, "") }
            if target.hasPrefix(rootPath + "/") {
                return (root, String(target.dropFirst(rootPath.count + 1)))
            }
        }
        return nil
    }

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func samePath(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    /// `path` if nothing exists there, otherwise "name (2).ext", "name (3).ext"…
    private func uniquePath(_ path: String) -> String {
        guard fileManager.fileExists(atPath: path) else { return path }
        let dir = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate) { return candidate }
            n += 1
        }
    }
}
