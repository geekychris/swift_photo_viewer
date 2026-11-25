import Foundation
import os.log

/// Executes a saved organise plan by copying files into a new target folder.
///
/// Safety rules: the source is never modified; nothing in the target is ever overwritten; each copy is
/// written under a temporary name, verified by SHA-256 against the catalogue, then renamed into place.
/// Progress is journalled in org_plan_items, so an interrupted run resumes where it stopped.
final class PlanExecutor {
    private static let logger = Logger(subsystem: "com.photomarger", category: "organise")
    private let db: DatabaseManager

    struct Progress {
        var done = 0
        var total = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        var failed = 0
        var current = ""
        var fraction: Double { bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : (total > 0 ? Double(done) / Double(total) : 0) }
    }

    struct Outcome {
        var verified = 0
        var alreadyPresent = 0
        var failed: [(String, String)] = []
        var manifestPath: String?
    }

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func execute(planId: Int64, target: URL, roots: [RootDirectory], concurrency: Int = 4,
                 progress: @escaping (Progress) -> Void) async throws -> Outcome {
        let all = try db.planItems(planId)
        let work = all.filter { $0.action == "copy" && $0.status != "verified" }
        var p = Progress(done: 0, total: work.count, bytesTotal: work.reduce(0) { $0 + $1.bytes })
        var outcome = Outcome()
        try db.setPlanStatus(planId, "running")

        let accessing = target.startAccessingSecurityScopedResource()
        defer { if accessing { target.stopAccessingSecurityScopedResource() } }

        try await SecurityScope.withAccess(roots) {
            var updates: [(id: Int64, status: String, error: String?)] = []
            try await withThrowingTaskGroup(of: (DatabaseManager.PlanItemRecord, Result<Bool, Error>).self) { group in
                var iterator = work.makeIterator()
                func enqueue() {
                    guard let item = iterator.next() else { return }
                    group.addTask(priority: .utility) {
                        do {
                            let existed = try Self.copyAndVerify(item, target: target)
                            return (item, .success(existed))
                        } catch {
                            return (item, .failure(error))
                        }
                    }
                }
                for _ in 0..<max(1, concurrency) { enqueue() }
                var lastReport = Date.distantPast
                while let (item, result) = try await group.next() {
                    try Task.checkCancellation()
                    p.done += 1
                    p.bytesDone += item.bytes
                    p.current = item.destRelativePath ?? ""
                    switch result {
                    case .success(let existed):
                        if existed { outcome.alreadyPresent += 1 } else { outcome.verified += 1 }
                        updates.append((item.id, "verified", nil))
                    case .failure(let error):
                        p.failed += 1
                        outcome.failed.append((item.sourcePath, error.localizedDescription))
                        updates.append((item.id, "failed", error.localizedDescription))
                        Self.logger.error("Copy failed \(item.sourcePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                    if updates.count >= 100 {
                        try db.updatePlanItems(updates)
                        updates.removeAll(keepingCapacity: true)
                    }
                    if Date().timeIntervalSince(lastReport) > 0.2 {
                        lastReport = Date()
                        progress(p)
                    }
                    enqueue()
                }
            }
            try db.updatePlanItems(updates)
        }
        progress(p)

        outcome.manifestPath = try? writeManifest(planId: planId, target: target)
        try db.setPlanStatus(planId, outcome.failed.isEmpty ? "done" : "partial")
        return outcome
    }

    /// Copies one item. Returns true when an identical file was already in place (resumed run).
    static func copyAndVerify(_ item: DatabaseManager.PlanItemRecord, target: URL) throws -> Bool {
        guard let rel = item.destRelativePath else { throw PlanError.noDestination }
        let fm = FileManager.default
        let dest = target.appendingPathComponent(rel)

        if fm.fileExists(atPath: dest.path) {
            if try FileScanningService.hashFile(atPath: dest.path) == item.fileHash { return true }
            throw PlanError.destinationOccupied(rel)
        }
        guard fm.fileExists(atPath: item.sourcePath) else { throw PlanError.sourceMissing(item.sourcePath) }

        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.lastPathComponent).pmpartial")
        try? fm.removeItem(at: partial)
        try fm.copyItem(at: URL(fileURLWithPath: item.sourcePath), to: partial)
        do {
            let hash = try FileScanningService.hashFile(atPath: partial.path)
            guard hash == item.fileHash else { throw PlanError.verificationFailed(item.sourcePath) }
            // moveItem refuses to replace an existing file, so a race can't overwrite anything.
            try fm.moveItem(at: partial, to: dest)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        return false
    }

    /// CSV of every decision (source, action, destination, reason, sha256) kept with the copied library.
    func writeManifest(planId: Int64, target: URL) throws -> String {
        func q(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = "source,action,destination,reason,status,sha256,bytes\n"
        for item in try db.planItems(planId) {
            csv += [q(item.sourcePath), item.action, q(item.destRelativePath), q(item.reason), item.status, item.fileHash, String(item.bytes)].joined(separator: ",") + "\n"
        }
        let dir = target.appendingPathComponent("_PhotoManager plans")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("plan-\(planId)-manifest.csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// Catalogue rows whose content is now safely in the target: copied-and-verified files and the
    /// exact duplicates of those. These are the only sources offered for trashing after a run.
    func sourcesSafeToTrash(planId: Int64, includeNearDuplicates: Bool) throws -> [Int64] {
        let items = try db.planItems(planId)
        let verifiedHashes = Set(items.filter { $0.action == "copy" && $0.status == "verified" }.map(\.fileHash))
        var ids: [Int64] = []
        for item in items {
            guard let id = item.photoId else { continue }
            if item.action == "copy" && item.status == "verified" {
                ids.append(id)
            } else if item.action == "skip", verifiedHashes.contains(item.fileHash) {
                ids.append(id)
            } else if item.action == "skip", includeNearDuplicates, (item.reason ?? "").hasPrefix("near-duplicate") {
                ids.append(id)
            }
        }
        return ids
    }
}

enum PlanError: Error, LocalizedError {
    case noDestination
    case sourceMissing(String)
    case destinationOccupied(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDestination: return "No destination"
        case .sourceMissing(let p): return "Source file is missing: \(p)"
        case .destinationOccupied(let p): return "A different file already exists at \(p); it was left untouched"
        case .verificationFailed(let p): return "Copy of \(p) did not match its catalogued checksum (has the file changed since the last scan?)"
        }
    }
}
