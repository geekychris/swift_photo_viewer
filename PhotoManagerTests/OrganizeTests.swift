import XCTest
@testable import PhotoManager

final class OrganizeEngineTests: XCTestCase {
    private var nextId: Int64 = 1

    private func photo(_ path: String, hash: String, at date: Date, camera: String? = "Canon EOS R5",
                       source: DateSource = .exif, size: Int64 = 1000, gps: (Double, Double)? = nil,
                       contentId: String? = nil, event: Int64? = nil, width: Int = 100) -> PhotoFile {
        defer { nextId += 1 }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        var p = PhotoFile(id: nextId, rootDirectoryId: 1, relativePath: path, fileName: name, fileExtension: ext,
                          fileSize: size, fileHash: hash, createdAt: date, modifiedAt: date, exifDateTaken: date,
                          exifCameraModel: camera, exifLensModel: nil, exifFocalLength: nil, exifAperture: nil, exifIso: nil,
                          exifShutterSpeed: nil, imageWidth: width, imageHeight: width, hasThumbnail: false, thumbnailPath: nil,
                          userDescription: nil, userTags: nil, rating: 0, colorTag: nil)
        p.captureDate = date
        p.dateSource = source
        p.mediaKind = MediaKind(fileExtension: ext) ?? .image
        p.gpsLatitude = gps?.0
        p.gpsLongitude = gps?.1
        p.contentIdentifier = contentId
        p.eventId = event
        return p
    }

    private func date(_ s: String) -> Date { FileScanningService.parseExifDate(s)! }

    func testNormalizedBaseName() {
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234 copy.JPG"), "img_1234")
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234 copy 2.JPG"), "img_1234")
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234 (1).jpg"), "img_1234")
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234 - Copy.jpg"), "img_1234")
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234 2.jpg"), "img_1234")
        XCTAssertEqual(OrganizeEngine.normalizedBaseName("IMG_1234_1.jpg"), "img_1234_1", "burst suffixes are not copies")
    }

    func testShotsPairRawJpegLivePhotosAndCollapseCopies() {
        let t = date("2019:03:12 10:00:00")
        let photos = [
            photo("card1/IMG_1.JPG", hash: "j1", at: t),
            photo("card1/IMG_1.CR2", hash: "r1", at: t),
            photo("backup/IMG_1.JPG", hash: "j1", at: t),          // exact copy
            photo("Desktop/IMG_1 copy.CR2", hash: "r1", at: t),    // exact copy, renamed
            photo("phone/IMG_9.HEIC", hash: "h9", at: t.addingTimeInterval(60), camera: "Apple iPhone", contentId: "C1"),
            photo("phone/IMG_9.MOV", hash: "m9", at: t.addingTimeInterval(61), camera: "Apple iPhone", contentId: "C1"),
            // Same name after the card counter rolled over, a year later: a different shot.
            photo("card9/IMG_1.JPG", hash: "j1b", at: t.addingTimeInterval(365 * 86400)),
        ]
        let (shots, stats) = OrganizeEngine.buildShots(photos)
        XCTAssertEqual(shots.count, 3)
        XCTAssertEqual(stats.duplicateFiles, 2)
        XCTAssertEqual(stats.rawJpegPairs, 1)
        XCTAssertEqual(stats.livePhotos, 1)
        let first = shots[0]
        XCTAssertEqual(Set(first.keepers.map(\.relativePath)), ["card1/IMG_1.JPG", "card1/IMG_1.CR2"])
        XCTAssertEqual(first.duplicates.count, 2)
        XCTAssertEqual(first.primary.fileExtension, "jpg")
    }

    func testNearDuplicatesAreFlaggedAndOptionallyDropped() {
        let t = date("2019:03:12 10:00:00")
        let photos = [
            photo("a/IMG_5.JPG", hash: "big", at: t, size: 5_000_000, width: 6000),
            photo("export/IMG_5.jpg", hash: "small", at: t, size: 300_000, width: 1200),
        ]
        let (shots, stats) = OrganizeEngine.buildShots(photos)
        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(stats.nearDuplicateShots, 1)

        let keepAll = OrganizeEngine.buildPlan(shots: shots, events: [])
        XCTAssertEqual(keepAll.summary.copyFiles, 2)
        XCTAssertEqual(Set(keepAll.entries.compactMap(\.destination)), ["2019/2019-03 Unsorted/IMG_5.JPG", "2019/2019-03 Unsorted/IMG_5_v2.jpg"])

        var options = OrganizeEngine.LayoutOptions()
        options.keepBestNearDuplicate = true
        let best = OrganizeEngine.buildPlan(shots: shots, events: [], options: options)
        XCTAssertEqual(best.summary.copyFiles, 1)
        XCTAssertEqual(best.summary.skippedNearDuplicates, 1)
        XCTAssertEqual(best.entries.first { $0.action == .copy }?.photo.fileHash, "big")
    }

    func testClustersSessionsTripsAndUndated() {
        var photos: [PhotoFile] = []
        // A day at home.
        photos.append(photo("h/1.jpg", hash: "1", at: date("2019:02:01 10:00:00")))
        photos.append(photo("h/2.jpg", hash: "2", at: date("2019:02:01 11:00:00")))
        // A three-day trip: Hong Kong then (same day, far away) Tokyo. Each anchor is a burst of 8 shots.
        func burst(_ tag: String, _ start: String, _ gps: (Double, Double)) {
            let t0 = date(start)
            for i in 0..<8 {
                photos.append(photo("t/\(tag)_\(i).jpg", hash: "\(tag)\(i)", at: t0.addingTimeInterval(Double(i) * 60), gps: gps))
            }
        }
        burst("a", "2019:03:12 09:00:00", (22.28, 114.17))
        burst("b", "2019:03:12 18:00:00", (22.30, 114.18))
        burst("c", "2019:03:13 10:00:00", (22.29, 114.16))
        burst("d", "2019:03:13 11:30:00", (35.68, 139.69))
        burst("e", "2019:03:14 10:00:00", (35.67, 139.70))
        // An everyday snap two evenings later stays out of the trip.
        photos.append(photo("h/9.jpg", hash: "9", at: date("2019:03:15 20:00:00")))
        // A scan with no reliable date.
        photos.append(photo("scans/old.tif", hash: "8", at: date("2024:01:01 00:00:00"), camera: nil, source: .file))

        let (shots, _) = OrganizeEngine.buildShots(photos)
        let clusters = OrganizeEngine.cluster(shots)
        XCTAssertEqual(clusters.map(\.kind), [.session, .trip, .session, .undated])
        let trip = clusters[1]
        XCTAssertEqual(trip.shots.count, 40)
        XCTAssertEqual(trip.days, 3)
        // Location jump splits the 13th into Hong Kong and Tokyo sessions.
        // 9 h and 16 h gaps split sessions; on the 13th the 1.5 h gap would not, but the jump to Tokyo does.
        XCTAssertEqual(trip.children.count, 5)
        XCTAssertEqual(clusters[0].shots.count, 2)
        XCTAssertEqual(clusters[3].shots.count, 1)
    }

    func testPlanLayoutWithEventsRawSubfolderAndCollisions() {
        let t = date("2019:03:12 10:00:00")
        let asia = PhotoEvent(id: 1, parentId: nil, name: "Asia Trip", kind: "trip", startDate: t)
        let hk = PhotoEvent(id: 2, parentId: 1, name: "Hong Kong", kind: "place", startDate: t)
        let temples = PhotoEvent(id: 3, parentId: 2, name: "Temples: Man Mo", kind: "subject", startDate: t)
        let photos = [
            photo("c/IMG_1.JPG", hash: "j1", at: t, event: 3),
            photo("c/IMG_1.CR2", hash: "r1", at: t, event: 3),
            // Different camera, same file name, same folder: needs a suffix that keeps its pair together.
            photo("d/IMG_1.JPG", hash: "j2", at: t.addingTimeInterval(600), camera: "Nikon Z6", event: 3),
            photo("d/IMG_1.NEF", hash: "r2", at: t.addingTimeInterval(600), camera: "Nikon Z6", event: 3),
            // RAW only: stays beside, not in RAW/.
            photo("c/IMG_2.CR2", hash: "r3", at: t.addingTimeInterval(1200), event: 2),
            photo("u/IMG_3.JPG", hash: "j3", at: date("2019:04:02 10:00:00")),
            photo("scans/s1.tif", hash: "s1", at: Date(), camera: nil, source: .file),
        ]
        let (shots, _) = OrganizeEngine.buildShots(photos)
        let plan = OrganizeEngine.buildPlan(shots: shots, events: [asia, hk, temples])
        let dests = Set(plan.entries.compactMap(\.destination))
        XCTAssertEqual(dests, [
            "2019/2019-03-12 Asia Trip/Hong Kong/Temples- Man Mo/IMG_1.JPG",
            "2019/2019-03-12 Asia Trip/Hong Kong/Temples- Man Mo/RAW/IMG_1.CR2",
            "2019/2019-03-12 Asia Trip/Hong Kong/Temples- Man Mo/IMG_1-2.JPG",
            "2019/2019-03-12 Asia Trip/Hong Kong/Temples- Man Mo/RAW/IMG_1-2.NEF",
            "2019/2019-03-12 Asia Trip/Hong Kong/IMG_2.CR2",
            "2019/2019-04 Unsorted/IMG_3.JPG",
            "Undated/scans/s1.tif",
        ])
        XCTAssertEqual(plan.summary.undatedFiles, 1)
        XCTAssertEqual(plan.summary.unsortedFiles, 1)
    }

    func testExecutorCopiesVerifiesAndNeverOverwrites() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("pm-exec-\(UUID().uuidString)")
        let source = base.appendingPathComponent("src"), target = base.appendingPathComponent("dst")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let a = source.appendingPathComponent("a.jpg"), b = source.appendingPathComponent("b.jpg")
        try Data("alpha".utf8).write(to: a)
        try Data("beta".utf8).write(to: b)
        let ha = try FileScanningService.hashFile(atPath: a.path), hb = try FileScanningService.hashFile(atPath: b.path)

        let item = DatabaseManager.PlanItemRecord(photoId: 1, sourcePath: a.path, destRelativePath: "2019/x/a.jpg",
                                                  action: "copy", reason: nil, fileHash: ha, bytes: 5)
        XCTAssertFalse(try PlanExecutor.copyAndVerify(item, target: target))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("2019/x/a.jpg"), encoding: .utf8), "alpha")
        // Re-running is a no-op.
        XCTAssertTrue(try PlanExecutor.copyAndVerify(item, target: target))
        // A different file at the destination is never replaced.
        let clash = DatabaseManager.PlanItemRecord(photoId: 2, sourcePath: b.path, destRelativePath: "2019/x/a.jpg",
                                                   action: "copy", reason: nil, fileHash: hb, bytes: 4)
        XCTAssertThrowsError(try PlanExecutor.copyAndVerify(clash, target: target))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("2019/x/a.jpg"), encoding: .utf8), "alpha")
        // A stale checksum (file changed since scan) fails and leaves nothing behind.
        let stale = DatabaseManager.PlanItemRecord(photoId: 3, sourcePath: b.path, destRelativePath: "2019/x/b.jpg",
                                                   action: "copy", reason: nil, fileHash: ha, bytes: 4)
        XCTAssertThrowsError(try PlanExecutor.copyAndVerify(stale, target: target))
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("2019/x/b.jpg").path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: target.appendingPathComponent("2019/x").path), ["a.jpg"])
    }

    func testGeoCellKeyMatchesSQL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-geo-\(UUID().uuidString).sqlite")
        let db = DatabaseManager(path: dir.path)
        for (lat, lon) in [(22.2783, 114.1747), (-33.865, 151.2094), (0.05, -0.05), (35.65, 139.75)] {
            let sql = try db.executeRawSQLSync("SELECT CAST(\(lat) * 10 AS INTEGER) || ',' || CAST(\(lon) * 10 AS INTEGER)")
            XCTAssertEqual(sql.first?.first ?? nil, GeoService.cellKey(latitude: lat, longitude: lon), "\(lat),\(lon)")
        }
    }
}
