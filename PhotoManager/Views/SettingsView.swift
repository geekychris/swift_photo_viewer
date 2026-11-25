import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var isCleaningThumbnails = false
    @State private var cleanupMessage: String?
    
    var body: some View {
        Form {
            Section("Database") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database Location")
                        .font(.headline)
                    
                    Text("~/Library/Application Support/PhotoManager/PhotoManager.sqlite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            Section("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thumbnails")
                        .font(.headline)
                    
                    Text("~/Library/Application Support/PhotoManager/Thumbnails/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    HStack(spacing: 8) {
                        Button("Clean Orphaned Thumbnails") {
                            cleanOrphanedThumbnails()
                        }
                        .disabled(isCleaningThumbnails)
                        .help("Deletes thumbnails of photos that are no longer in the catalogue")
                        
                        if isCleaningThumbnails {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    
                    if let cleanupMessage {
                        Text(cleanupMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PhotoManager")
                        .font(.headline)
                    
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("A photo management application for organizing and browsing your photo collections.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
    }
    
    private func cleanOrphanedThumbnails() {
        isCleaningThumbnails = true
        cleanupMessage = nil
        Task {
            do {
                let summary = try await Self.removeOrphanedThumbnails()
                cleanupMessage = summary
            } catch {
                cleanupMessage = "Cleanup failed: \(error.localizedDescription)"
            }
            ThumbnailCache.shared.removeAll()
            isCleaningThumbnails = false
        }
    }
    
    /// Deletes content-addressed thumbnails (Thumbnails/<2-char shard>/<sha256>.jpg) whose hash has no
    /// catalogue row, and legacy thumbnails (Thumbnails/<id>_<hash8>.jpg) no row references.
    /// Files modified in the last 10 minutes are skipped so a running scan is not raced.
    private static func removeOrphanedThumbnails() async throws -> String {
        let (_, hashRows) = try await DatabaseManager.shared.executeRawSQL("SELECT DISTINCT file_hash FROM photo_files")
        let (_, pathRows) = try await DatabaseManager.shared.executeRawSQL(
            "SELECT DISTINCT thumbnail_path FROM photo_files WHERE thumbnail_path IS NOT NULL AND thumbnail_path != ''")
        let knownHashes = Set(hashRows.compactMap { $0["file_hash"] })
        let referencedNames = Set(pathRows.compactMap { $0["thumbnail_path"] }.map { ($0 as NSString).lastPathComponent })
        let directory = ThumbnailService.thumbnailDirectory
        
        return try await Task.detached(priority: .utility) { () -> String in
            let fm = FileManager.default
            let cutoff = Date().addingTimeInterval(-600)
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            var removed = 0, kept = 0, failed = 0
            var freed: Int64 = 0
            
            func consider(_ url: URL, orphaned: Bool) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return }
                guard orphaned, (values.contentModificationDate ?? .distantFuture) < cutoff else { kept += 1; return }
                do {
                    try fm.removeItem(at: url)
                    removed += 1
                    freed += Int64(values.fileSize ?? 0)
                } catch {
                    failed += 1
                }
            }
            
            for entry in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) {
                try Task.checkCancellation()
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    // Shard directory: <2 chars>/<hash>.jpg
                    guard entry.lastPathComponent.count == 2 else { continue }
                    let files = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: keys)) ?? []
                    for file in files where file.pathExtension.lowercased() == "jpg" {
                        let hash = file.deletingPathExtension().lastPathComponent
                        consider(file, orphaned: !knownHashes.contains(hash) && !referencedNames.contains(file.lastPathComponent))
                    }
                } else if entry.pathExtension.lowercased() == "jpg" {
                    // Legacy flat file: <id>_<hash8>.jpg
                    consider(entry, orphaned: !referencedNames.contains(entry.lastPathComponent))
                }
            }
            
            var summary = "Removed \(removed) orphaned thumbnail\(removed == 1 ? "" : "s") (\(DuplicateFormat.size(freed))), kept \(kept)"
            if failed > 0 { summary += ", \(failed) could not be removed" }
            return summary + "."
        }.value
    }
}
