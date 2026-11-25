import XCTest
@testable import PhotoManager

/// End-to-end timing on a generated library. Skipped unless PM_BENCH_LIBRARY names a folder the
/// sandboxed test host can read (e.g. inside ~/Library/Containers/com.example.PhotoManager/Data/tmp):
///
///   python3 tools/make_synthetic_library.py ~/Library/Containers/com.example.PhotoManager/Data/tmp/pm-bench --shots 20000
///   TEST_RUNNER_PM_BENCH_LIBRARY=~/Library/Containers/com.example.PhotoManager/Data/tmp/pm-bench \
///     xcodebuild test -scheme PhotoManager -only-testing:PhotoManagerTests/BenchmarkTests
final class BenchmarkTests: XCTestCase {
    func testScanOrganiseAndQueryLargeLibrary() async throws {
        guard let path = ProcessInfo.processInfo.environment["PM_BENCH_LIBRARY"] else {
            throw XCTSkip("Set PM_BENCH_LIBRARY to run")
        }
        let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).sqlite").path
        let db = DatabaseManager(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let rootId = try db.addRootDirectory(RootDirectory(path: path, name: "bench"))
        let root = try XCTUnwrap(db.getRootDirectories().first { $0.id == rootId })
        let scanner = FileScanningService(databaseManager: db)

        func time<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
            let start = Date()
            let result = try await body()
            print(String(format: "BENCH %-34@ %8.3f s", label as NSString, Date().timeIntervalSince(start)))
            return result
        }

        let first = try await time("full scan") { try await scanner.scanDirectory(root) }
        print("BENCH files found: \(first.found), failed: \(first.failed)")
        XCTAssertEqual(first.failed, 0)
        let again = try await time("rescan, nothing changed") { try await scanner.scanDirectory(root) }
        XCTAssertEqual(again.unchanged, first.found)

        let count = try await time("count all") { try db.countPhotos(matching: .all) }
        XCTAssertEqual(count.count, first.found)
        _ = try await time("first grid page (200)") { try db.photos(matching: .all, limit: 200) }
        _ = try await time("deep grid page (offset 20000)") { try db.photos(matching: .all, limit: 200, offset: 20_000) }
        _ = try await time("timeline by day") { try db.pivot(.day) }
        _ = try await time("pivot month x camera") { try db.pivot(.month, by: .camera) }
        let groups = try await time("duplicate groups") { try db.findDuplicates() }
        _ = try await time("duplicates by directory") { try db.findDuplicatesByDirectory(groups: groups) }
        _ = try await time("complete duplicate directories") { try db.findCompleteDuplicateDirectories() }

        let photos = try await time("load all rows") { try db.photos(matching: .all, sort: .captureAscending) }
        let (shots, stats) = await time("build shots") { OrganizeEngine.buildShots(photos) }
        let clusters = await time("cluster") { OrganizeEngine.cluster(shots) }
        let plan = await time("build plan") { OrganizeEngine.buildPlan(shots: shots, events: []) }
        print("BENCH shots \(stats.shots), dup files \(stats.duplicateFiles), pairs \(stats.rawJpegPairs), near \(stats.nearDuplicateShots), undated \(stats.undatedShots)")
        print("BENCH clusters \(clusters.count) (trips \(clusters.filter { $0.kind == .trip }.count))")
        print("BENCH plan: \(plan.summary.text)")

        // Ground truth from the generator.
        if let data = FileManager.default.contents(atPath: (path as NSString).appendingPathComponent("expected.json")),
           let truth = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            XCTAssertEqual(stats.duplicateFiles, truth["duplicate_files"] as? Int)
            XCTAssertEqual(stats.shots, truth["unique_shots"] as? Int)
            XCTAssertEqual(stats.nearDuplicateShots, truth["near_duplicates"] as? Int)
            // Every generated trip should come out as exactly one detected trip with the same days.
            let trips = clusters.filter { $0.kind == .trip }
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            let detected = Set(trips.map { "\(day.string(from: $0.start))/\($0.days)" })
            let expected = (truth["trips"] as? [[String: Any]] ?? []).map { t in
                "\((t["start"] as? String ?? "").prefix(10))/\(t["days"] as? Int ?? 0)"
            }
            let missed = expected.filter { !detected.contains($0) }
            print("BENCH trips expected \(expected.count), detected \(trips.count), missed \(missed.count): \(missed.prefix(5))")
            for m in missed {
                let startDay = day.date(from: String(m.prefix(10)))!
                let near = clusters.filter { abs($0.start.timeIntervalSince(startDay)) < 4 * 86400 }
                print("BENCH   missed \(m): nearby " + near.map { "\($0.kind.rawValue) \(day.string(from: $0.start))/\($0.days)d/\($0.shots.count)s" }.joined(separator: ", "))
            }
            XCTAssertTrue(missed.isEmpty)
            XCTAssertEqual(trips.count, expected.count)
        }
    }
}
