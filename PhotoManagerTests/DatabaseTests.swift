import XCTest
import SQLite
@testable import PhotoManager

final class DatabaseTests: XCTestCase {
    var dir: URL!
    var db: DatabaseManager!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        db = DatabaseManager(path: dir.appendingPathComponent("test.sqlite").path)
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: dir)
    }

    static func scanned(_ root: Int64, _ path: String, hash: String, date: Date = Date(timeIntervalSince1970: 1_552_000_000),
                        size: Int64 = 100, camera: String? = "Canon EOS R5") -> ScannedFile {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        return ScannedFile(rootDirectoryId: root, relativePath: path, fileName: name, fileExtension: ext,
                           mediaKind: MediaKind(fileExtension: ext) ?? .image, fileSize: size, fileHash: hash,
                           createdAt: date, modifiedAt: date, exifDateTaken: date, captureDate: date, dateSource: .exif,
                           cameraModel: camera, lensModel: nil, focalLength: 35, aperture: 2.8, iso: 100, shutterSpeed: "1/125s",
                           imageWidth: 10, imageHeight: 10, gpsLatitude: nil, gpsLongitude: nil, contentIdentifier: nil, duration: nil)
    }

    func addRoot(_ name: String = "root") throws -> Int64 {
        try db.addRootDirectory(RootDirectory(path: dir.appendingPathComponent(name).path, name: name))
    }

    func testUpsertPreservesUserDataAndResetsThumbnailOnContentChange() throws {
        let root = try addRoot()
        try db.upsert([Self.scanned(root, "a/IMG_1.JPG", hash: "h1")])
        let id = try XCTUnwrap(db.photos(matching: .all).first?.id)
        try db.updatePhotoRating(id, rating: 4)
        try db.updatePhotoMetadata(id, description: "temple", tags: "asia, temple")
        try db.setThumbnails([("h1", "/tmp/h1.jpg")])

        // Same content rescanned: everything kept.
        try db.upsert([Self.scanned(root, "a/IMG_1.JPG", hash: "h1")])
        var photo = try XCTUnwrap(db.getPhotoById(id))
        XCTAssertEqual(photo.rating, 4)
        XCTAssertEqual(photo.userDescription, "temple")
        XCTAssertTrue(photo.hasThumbnail)

        // Edited file: user data kept, thumbnail invalidated, still one row.
        try db.upsert([Self.scanned(root, "a/IMG_1.JPG", hash: "h2")])
        photo = try XCTUnwrap(db.getPhotoById(id))
        XCTAssertEqual(photo.rating, 4)
        XCTAssertEqual(photo.fileHash, "h2")
        XCTAssertFalse(photo.hasThumbnail)
        XCTAssertEqual(try db.countPhotos(matching: .all).count, 1)
        XCTAssertEqual(Set(try db.tags(forPhoto: id).map(\.name)), ["asia", "temple"])
    }

    func testDuplicatesAndDirectoryViews() throws {
        let root = try addRoot()
        try db.upsert([
            Self.scanned(root, "card1/IMG_1.JPG", hash: "h1"),
            Self.scanned(root, "card1/IMG_2.JPG", hash: "h2"),
            Self.scanned(root, "copy/IMG_1.JPG", hash: "h1"),
            Self.scanned(root, "copy/IMG_2.JPG", hash: "h2"),
            Self.scanned(root, "other/IMG_3.JPG", hash: "h3"),
            Self.scanned(root, "other/IMG_1 copy.JPG", hash: "h1"),
        ])
        let groups = try db.findDuplicates()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first { $0.fileHash == "h1" }?.files.count, 3)

        let byDir = try db.findDuplicatesByDirectory(groups: groups)
        let other = try XCTUnwrap(byDir.first { $0.directoryPath == "other" })
        XCTAssertEqual(other.fileCount, 2)
        XCTAssertEqual(other.duplicateFileCount, 1)

        let complete = try db.findCompleteDuplicateDirectories()
        XCTAssertEqual(complete.count, 1)
        XCTAssertEqual(Set(complete[0].allDirectories.map(\.relativePath)), ["card1", "copy"])
    }

    func testFiltersAndPivot() throws {
        let root = try addRoot()
        let march = FileScanningService.parseExifDate("2019:03:12 10:00:00")!
        let april = FileScanningService.parseExifDate("2019:04:02 10:00:00")!
        try db.upsert([
            Self.scanned(root, "trip/a.jpg", hash: "1", date: march),
            Self.scanned(root, "trip/a.cr2", hash: "2", date: march),
            Self.scanned(root, "trip/sub/b.jpg", hash: "3", date: april, camera: "Apple iPhone 15 Pro"),
        ])
        var f = PhotoFilter()
        f.capturePrefix = "2019-03"
        XCTAssertEqual(try db.countPhotos(matching: f).count, 2)

        f = PhotoFilter()
        f.directoryPath = "trip"
        XCTAssertEqual(try db.countPhotos(matching: f).count, 2)
        f.includeSubdirectories = true
        XCTAssertEqual(try db.countPhotos(matching: f).count, 3)

        f = PhotoFilter()
        f.mediaKinds = [.raw]
        XCTAssertEqual(try db.photos(matching: f).map(\.fileName), ["a.cr2"])

        let byMonth = try db.pivot(.month)
        XCTAssertEqual(byMonth.map(\.key), ["2019-03", "2019-04"])
        let matrix = try db.pivot(.month, by: .camera)
        XCTAssertEqual(matrix.count, 2)

        let page = try db.photos(matching: .all, sort: .captureAscending, limit: 2, offset: 1)
        XCTAssertEqual(page.count, 2)
    }

    func testEventsRollUpAndAssignment() throws {
        let root = try addRoot()
        try db.upsert((1...4).map { Self.scanned(root, "x/\($0).jpg", hash: "h\($0)") })
        let ids = try db.photoIds(matching: .all)
        let trip = try db.createEvent(name: "Asia Trip", parentId: nil, kind: "trip")
        let hk = try db.createEvent(name: "Hong Kong", parentId: trip, kind: "place")
        let temples = try db.createEvent(name: "Temples", parentId: hk)
        try db.assignPhotos(Array(ids.prefix(2)), toEvent: temples)
        try db.assignPhotos([ids[2]], toEvent: hk)

        let events = Dictionary(uniqueKeysWithValues: try db.events().map { ($0.id, $0) })
        XCTAssertEqual(events[trip]?.photoCount, 3)
        XCTAssertEqual(events[temples]?.photoCount, 2)
        XCTAssertEqual(db.eventPath(temples, events: events).map(\.name), ["Asia Trip", "Hong Kong", "Temples"])

        var f = PhotoFilter()
        f.eventId = trip
        XCTAssertEqual(try db.countPhotos(matching: f).count, 3)
        f.unassignedOnly = false
        f = PhotoFilter()
        f.unassignedOnly = true
        XCTAssertEqual(try db.countPhotos(matching: f).count, 1)

        XCTAssertThrowsError(try db.moveEvent(trip, toParent: temples))
        try db.deleteEvent(trip)
        XCTAssertEqual(try db.countPhotos(matching: f).count, 4)
    }

    func testDeletingRootCascades() throws {
        let root = try addRoot()
        try db.upsert([Self.scanned(root, "a.jpg", hash: "1")])
        try db.deleteRootDirectory(root)
        XCTAssertEqual(try db.countPhotos(matching: .all).count, 0)
    }

    func testMigratesV1DatabaseKeepingUserData() throws {
        let path = dir.appendingPathComponent("v1.sqlite").path
        let raw = try Connection(path)
        try raw.execute("""
            CREATE TABLE root_directories (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, last_scanned_at TEXT, bookmark_data BLOB);
            CREATE TABLE photo_files (id INTEGER PRIMARY KEY AUTOINCREMENT, root_directory_id INTEGER NOT NULL, relative_path TEXT NOT NULL,
                file_name TEXT NOT NULL, file_extension TEXT NOT NULL, file_size INTEGER NOT NULL, file_hash TEXT NOT NULL,
                created_at TEXT NOT NULL, modified_at TEXT NOT NULL, exif_date_taken TEXT, exif_camera_model TEXT, exif_lens_model TEXT,
                exif_focal_length REAL, exif_aperture REAL, exif_iso INTEGER, exif_shutter_speed TEXT, image_width INTEGER,
                image_height INTEGER, has_thumbnail INTEGER NOT NULL DEFAULT 0, thumbnail_path TEXT, user_description TEXT,
                user_tags TEXT, rating INTEGER DEFAULT 0, color_tag TEXT);
            INSERT INTO root_directories (id, path, name, created_at) VALUES (1, '/photos', 'photos', '2025-11-05T10:00:00.000');
            INSERT INTO photo_files (root_directory_id, relative_path, file_name, file_extension, file_size, file_hash, created_at, modified_at,
                exif_date_taken, user_description, user_tags, rating, color_tag)
              VALUES (1, 'Trip/IMG_1.JPG', 'IMG_1.JPG', 'JPG', 10, 'aaa', '2019-03-12T02:00:00.000', '2019-03-12T02:00:00.000',
                      '2019-03-12T02:00:00.000', 'old desc', 'asia', 5, 'red');
            -- The duplicate row the old fast scan created for the same path, without user data.
            INSERT INTO photo_files (root_directory_id, relative_path, file_name, file_extension, file_size, file_hash, created_at, modified_at)
              VALUES (1, 'Trip/IMG_1.JPG', 'IMG_1.JPG', 'JPG', 11, 'bbb', '2019-03-12T02:00:00.000', '2020-01-01T00:00:00.000');
            -- An orphan left by the missing foreign-key pragma.
            INSERT INTO photo_files (root_directory_id, relative_path, file_name, file_extension, file_size, file_hash, created_at, modified_at)
              VALUES (99, 'gone.jpg', 'gone.jpg', 'jpg', 1, 'ccc', '2019-03-12T02:00:00.000', '2019-03-12T02:00:00.000');
            """)

        let migrated = DatabaseManager(path: path)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("v1.v0-backup-") }
        XCTAssertEqual(backups.count, 1, "a backup is written before migrating")
        let photos = try migrated.photos(matching: .all)
        XCTAssertEqual(photos.count, 1)
        let photo = try XCTUnwrap(photos.first)
        XCTAssertEqual(photo.fileHash, "bbb", "the newest row's file data wins")
        XCTAssertEqual(photo.rating, 5)
        XCTAssertEqual(photo.userDescription, "old desc")
        XCTAssertEqual(photo.colorTag, "red")
        XCTAssertEqual(photo.directoryPath, "Trip")
        XCTAssertEqual(photo.fileExtension, "jpg")
        XCTAssertEqual(photo.dateSource, .file, "the newest row had no EXIF date")
        XCTAssertEqual(try migrated.tags(forPhoto: photo.id!).map(\.name), ["asia"])
    }
}

final class ParsingTests: XCTestCase {
    func testFilenameDates() {
        let cal = Calendar.current
        let d1 = FileScanningService.dateFromFilename("IMG_20190312_101502.jpg")!
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d1),
                       DateComponents(year: 2019, month: 3, day: 12, hour: 10, minute: 15, second: 2))
        let d2 = FileScanningService.dateFromFilename("2019-03-12 10.15.02.jpg")!
        XCTAssertEqual(cal.component(.minute, from: d2), 15)
        let d3 = FileScanningService.dateFromFilename("Scan_19980704.tif")!
        XCTAssertEqual(cal.component(.year, from: d3), 1998)
        XCTAssertNil(FileScanningService.dateFromFilename("IMG_1234.JPG"))
        XCTAssertNil(FileScanningService.dateFromFilename("DSC_20191399.JPG"))
    }

    func testQuickTimeDateKeepsWallClock() {
        let d = FileScanningService.parseQuickTimeDate("2019-03-12T10:15:02+0800")!
        XCTAssertEqual(Calendar.current.component(.hour, from: d), 10)
    }

    func testISO6709() {
        let (lat, lon) = FileScanningService.parseISO6709("+22.2783+114.1747+010.000/")!
        XCTAssertEqual(lat, 22.2783, accuracy: 1e-6)
        XCTAssertEqual(lon, 114.1747, accuracy: 1e-6)
    }

    func testWeekRangeMatchesSQLite() throws {
        // 2019-01-01 was a Tuesday; first Monday is Jan 7, which SQLite calls week 01.
        let range = try XCTUnwrap(PhotoFilter.weekRange("2019-W01"))
        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.month, .day], from: range.lowerBound), DateComponents(month: 1, day: 7))
        let w0 = try XCTUnwrap(PhotoFilter.weekRange("2019-W00"))
        XCTAssertEqual(cal.component(.day, from: w0.lowerBound), 1)
    }
}

final class MigrationSafetyTests: XCTestCase {
    func testSharedDatabaseIsNotTheRealCatalogueUnderTests() {
        XCTAssertTrue(DatabaseManager.shared.databasePath.contains("PhotoManager-test-host-"))
    }
}
