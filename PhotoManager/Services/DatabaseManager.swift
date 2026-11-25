import Foundation
import SQLite
import os.log

/// One file as produced by the scanner, ready to upsert. User data (rating, tags, description,
/// colour, event) is never part of this, so a rescan cannot overwrite it.
struct ScannedFile {
    let rootDirectoryId: Int64
    let relativePath: String
    let fileName: String
    let fileExtension: String
    let mediaKind: MediaKind
    let fileSize: Int64
    let fileHash: String
    let createdAt: Date
    let modifiedAt: Date
    let exifDateTaken: Date?
    let captureDate: Date
    let dateSource: DateSource
    let cameraModel: String?
    let lensModel: String?
    let focalLength: Double?
    let aperture: Double?
    let iso: Int?
    let shutterSpeed: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let contentIdentifier: String?
    let duration: Double?
}

/// Lightweight row the scanner compares against to skip unchanged files.
struct IndexedFile {
    let id: Int64
    let fileSize: Int64
    let modifiedAt: Double
    let fileHash: String
}

/// One cell of an analytics pivot.
struct PivotRow: Identifiable, Hashable {
    var id: String { "\(key)|\(key2 ?? "")" }
    let key: String
    let key2: String?
    let count: Int
    let bytes: Int64
}

/// Dimensions the analytics view can group by. Each maps to a SQL expression over photo_files `p`.
enum PivotDimension: String, CaseIterable, Identifiable {
    case year, month, day, week, weekday, hour
    case event, topEvent, person, keyword
    case country, city
    case camera, lens, focalLength, iso, aperture
    case mediaKind, fileExtension, rating, colorTag, dateSource, root, directory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: return "Year"
        case .month: return "Month"
        case .day: return "Day"
        case .week: return "Week"
        case .weekday: return "Weekday"
        case .hour: return "Hour of day"
        case .event: return "Event"
        case .topEvent: return "Trip / top event"
        case .person: return "Person"
        case .keyword: return "Keyword"
        case .country: return "Country"
        case .city: return "City"
        case .camera: return "Camera"
        case .lens: return "Lens"
        case .focalLength: return "Focal length"
        case .iso: return "ISO"
        case .aperture: return "Aperture"
        case .mediaKind: return "Media kind"
        case .fileExtension: return "File type"
        case .rating: return "Rating"
        case .colorTag: return "Colour tag"
        case .dateSource: return "Date source"
        case .root: return "Library root"
        case .directory: return "Folder"
        }
    }
}

class DatabaseManager: ObservableObject {
    /// The app's catalogue. Under XCTest (the test host launches the app) a throwaway database is
    /// used instead, so running tests can never migrate or modify the real catalogue.
    static let shared: DatabaseManager = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoManager-test-host-\(UUID().uuidString).sqlite").path
            return DatabaseManager(path: path)
        }
        return DatabaseManager()
    }()
    private static let logger = Logger(subsystem: "com.photomarger", category: "database")

    static let schemaVersion: Int32 = 2

    private var db: Connection?
    let databasePath: String

    /// Columns read by `mapPhoto`, in positional order.
    static let photoColumns = """
        p.id, p.root_directory_id, p.relative_path, p.file_name, p.file_extension, p.file_size, p.file_hash,
        p.created_at, p.modified_at, p.exif_date_taken, p.exif_camera_model, p.exif_lens_model, p.exif_focal_length,
        p.exif_aperture, p.exif_iso, p.exif_shutter_speed, p.image_width, p.image_height, p.has_thumbnail,
        p.thumbnail_path, p.user_description, p.user_tags, p.rating, p.color_tag, p.capture_date, p.date_source,
        p.media_kind, p.gps_lat, p.gps_lon, p.content_id, p.event_id
        """

    /// - Parameter path: database file; nil uses Application Support/PhotoManager/PhotoManager.sqlite.
    init(path: String? = nil) {
        if let path {
            databasePath = path
        } else {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupportURL.appendingPathComponent("PhotoManager")
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            databasePath = appDirectory.appendingPathComponent("PhotoManager.sqlite").path
        }
        Self.logger.info("Database path: \(self.databasePath, privacy: .public)")

        do {
            let connection = try Connection(databasePath)
            connection.busyTimeout = 10
            try connection.execute("""
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = NORMAL;
                PRAGMA temp_store = MEMORY;
                PRAGMA cache_size = -65536;
                """)
            db = connection
            try migrate(connection)
            // Must be set outside a transaction; SQLite ignores foreign keys (and ON DELETE CASCADE) without it.
            try connection.execute("PRAGMA foreign_keys = ON")
        } catch {
            Self.logger.error("Database setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func conn() throws -> Connection {
        guard let db else { throw DatabaseError.connectionFailed }
        return db
    }

    // MARK: - Schema

    private static let photoFilesV2DDL = """
        CREATE TABLE IF NOT EXISTS %@ (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_directory_id INTEGER NOT NULL REFERENCES root_directories(id) ON DELETE CASCADE,
            relative_path TEXT NOT NULL,
            dir_path TEXT NOT NULL DEFAULT '',
            file_name TEXT NOT NULL,
            base_name TEXT NOT NULL DEFAULT '',
            file_extension TEXT NOT NULL,
            media_kind TEXT NOT NULL DEFAULT 'image',
            file_size INTEGER NOT NULL DEFAULT 0,
            file_hash TEXT NOT NULL,
            created_at REAL NOT NULL DEFAULT 0,
            modified_at REAL NOT NULL DEFAULT 0,
            exif_date_taken REAL,
            capture_date REAL NOT NULL DEFAULT 0,
            capture_local TEXT NOT NULL DEFAULT '',
            date_source TEXT NOT NULL DEFAULT 'file',
            exif_camera_model TEXT,
            exif_lens_model TEXT,
            exif_focal_length REAL,
            exif_aperture REAL,
            exif_iso INTEGER,
            exif_shutter_speed TEXT,
            image_width INTEGER,
            image_height INTEGER,
            gps_lat REAL,
            gps_lon REAL,
            content_id TEXT,
            duration REAL,
            has_thumbnail INTEGER NOT NULL DEFAULT 0,
            thumbnail_path TEXT,
            user_description TEXT,
            user_tags TEXT,
            rating INTEGER NOT NULL DEFAULT 0,
            color_tag TEXT,
            event_id INTEGER REFERENCES events(id) ON DELETE SET NULL,
            UNIQUE(root_directory_id, relative_path)
        )
        """

    private static let supportingDDL = """
        CREATE TABLE IF NOT EXISTS root_directories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            last_scanned_at TEXT,
            bookmark_data BLOB
        );
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_id INTEGER REFERENCES events(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'event',
            place TEXT,
            notes TEXT,
            sort_key REAL NOT NULL DEFAULT 0,
            created_at REAL NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_events_parent ON events(parent_id);
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'keyword',
            UNIQUE(name COLLATE NOCASE, kind)
        );
        CREATE TABLE IF NOT EXISTS photo_tags (
            photo_id INTEGER NOT NULL REFERENCES photo_files(id) ON DELETE CASCADE,
            tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (photo_id, tag_id)
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS idx_photo_tags_tag ON photo_tags(tag_id);
        CREATE TABLE IF NOT EXISTS geo_cells (
            cell TEXT PRIMARY KEY,
            country TEXT,
            locality TEXT,
            area TEXT,
            looked_up_at REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS org_plans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            target_root TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'draft',
            summary TEXT
        );
        CREATE TABLE IF NOT EXISTS org_plan_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plan_id INTEGER NOT NULL REFERENCES org_plans(id) ON DELETE CASCADE,
            photo_id INTEGER,
            source_path TEXT NOT NULL,
            dest_rel_path TEXT,
            action TEXT NOT NULL,
            reason TEXT,
            file_hash TEXT NOT NULL,
            bytes INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_plan_items_plan ON org_plan_items(plan_id, status);
        """

    private static let photoIndexesDDL = """
        CREATE INDEX IF NOT EXISTS idx_photo_hash ON photo_files(file_hash);
        CREATE INDEX IF NOT EXISTS idx_photo_root_dir ON photo_files(root_directory_id, dir_path);
        CREATE INDEX IF NOT EXISTS idx_photo_capture_local ON photo_files(capture_local);
        CREATE INDEX IF NOT EXISTS idx_photo_capture_date ON photo_files(capture_date);
        CREATE INDEX IF NOT EXISTS idx_photo_event ON photo_files(event_id);
        CREATE INDEX IF NOT EXISTS idx_photo_rating ON photo_files(rating);
        CREATE INDEX IF NOT EXISTS idx_photo_color_tag ON photo_files(color_tag);
        CREATE INDEX IF NOT EXISTS idx_photo_base_name ON photo_files(base_name);
        """

    private func migrate(_ db: Connection) throws {
        let version = db.userVersion ?? 0
        if version >= Self.schemaVersion { return }

        let hasV1Photos = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='photo_files'") as? Int64 ?? 0 > 0
        if hasV1Photos { try backUpBeforeMigration(db, fromVersion: version) }

        try db.execute("PRAGMA foreign_keys = OFF")
        try db.transaction {
            try db.execute(Self.supportingDDL)
            if hasV1Photos {
                try migrateV1Photos(db)
            } else {
                try db.execute(String(format: Self.photoFilesV2DDL, "photo_files"))
            }
            try db.execute(Self.photoIndexesDDL)
            db.userVersion = Self.schemaVersion
        }
        if hasV1Photos {
            try migrateUserTagsToTagTable(db)
        }
        Self.logger.info("Database migrated to schema v\(Self.schemaVersion)")
    }

    /// Copies the database next to itself (PhotoManager.v1-backup-<timestamp>.sqlite) before a migration.
    private func backUpBeforeMigration(_ db: Connection, fromVersion version: Int32) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = (databasePath as NSString).deletingPathExtension
        let backup = "\(base).v\(version)-backup-\(formatter.string(from: Date())).sqlite"
        // VACUUM INTO writes a consistent single-file copy, including anything still in the WAL.
        try db.run("VACUUM INTO ?", backup)
        Self.logger.info("Backed up database to \(backup, privacy: .public) before migrating")
    }
    
    /// Rebuilds photo_files with the v2 layout. Dates become epoch seconds, rows duplicated by the old
    /// fast-scan bug (same root + path) collapse into one that keeps any rating, tags or description,
    /// and rows orphaned by the missing foreign-key pragma are dropped.
    private func migrateV1Photos(_ db: Connection) throws {
        let existing = Set(try db.prepare("PRAGMA table_info(photo_files)").compactMap { $0[1] as? String })
        func epoch(_ expr: String) -> String { "(julianday(\(expr)) - 2440587.5) * 86400.0" }

        let captureLocal = "COALESCE(datetime(julianday(p.exif_date_taken), 'localtime'), datetime(julianday(p.modified_at), 'localtime'), '')"
        func latest(_ name: String) -> String {
            guard existing.contains(name) else { return "NULL" }
            return "(SELECT q.\(name) FROM photo_files q WHERE q.root_directory_id = p.root_directory_id AND q.relative_path = p.relative_path AND q.\(name) IS NOT NULL ORDER BY q.id DESC LIMIT 1)"
        }
        let rating = existing.contains("rating")
            ? "COALESCE((SELECT MAX(q.rating) FROM photo_files q WHERE q.root_directory_id = p.root_directory_id AND q.relative_path = p.relative_path), 0)"
            : "0"

        try db.execute(String(format: Self.photoFilesV2DDL, "photo_files_v2"))
        try db.execute("""
            INSERT INTO photo_files_v2 (
                id, root_directory_id, relative_path, file_name, file_extension, file_size, file_hash,
                created_at, modified_at, exif_date_taken, capture_local, capture_date, date_source,
                exif_camera_model, exif_lens_model, exif_focal_length, exif_aperture, exif_iso, exif_shutter_speed,
                image_width, image_height, has_thumbnail, thumbnail_path,
                user_description, user_tags, rating, color_tag)
            SELECT
                p.id, p.root_directory_id, p.relative_path, p.file_name, lower(p.file_extension), p.file_size, p.file_hash,
                COALESCE(\(epoch("p.created_at")), 0), COALESCE(\(epoch("p.modified_at")), 0), \(epoch("p.exif_date_taken")),
                \(captureLocal), COALESCE(\(epoch("p.exif_date_taken")), \(epoch("p.modified_at")), 0),
                CASE WHEN p.exif_date_taken IS NOT NULL THEN 'exif' ELSE 'file' END,
                p.exif_camera_model, p.exif_lens_model, p.exif_focal_length, p.exif_aperture, p.exif_iso, p.exif_shutter_speed,
                p.image_width, p.image_height, COALESCE(p.has_thumbnail, 0), p.thumbnail_path,
                \(latest("user_description")), \(latest("user_tags")), \(rating), \(latest("color_tag"))
            FROM photo_files p
            WHERE p.id IN (SELECT MAX(id) FROM photo_files GROUP BY root_directory_id, relative_path)
              AND p.root_directory_id IN (SELECT id FROM root_directories)
            """)
        try db.execute("DROP TABLE photo_files")
        try db.execute("ALTER TABLE photo_files_v2 RENAME TO photo_files")

        // Columns derived from the path are simplest to fill in Swift.
        let update = try db.prepare("UPDATE photo_files SET dir_path = ?, base_name = ?, media_kind = ? WHERE id = ?")
        for row in try db.prepare("SELECT id, relative_path, file_name, file_extension FROM photo_files") {
            guard let id = row[0] as? Int64, let rel = row[1] as? String,
                  let name = row[2] as? String, let ext = row[3] as? String else { continue }
            let kind = MediaKind(fileExtension: ext) ?? .image
            try update.run((rel as NSString).deletingLastPathComponent,
                           ((name as NSString).deletingPathExtension).lowercased(),
                           kind.rawValue, id)
        }
    }

    private func migrateUserTagsToTagTable(_ db: Connection) throws {
        var pairs: [(Int64, String)] = []
        for row in try db.prepare("SELECT id, user_tags FROM photo_files WHERE user_tags IS NOT NULL AND user_tags != ''") {
            guard let id = row[0] as? Int64, let tags = row[1] as? String else { continue }
            for tag in Self.splitTags(tags) { pairs.append((id, tag)) }
        }
        guard !pairs.isEmpty else { return }
        try db.transaction {
            for (photoId, name) in pairs {
                let tagId = try tagId(named: name, kind: .keyword, db: db)
                try db.run("INSERT OR IGNORE INTO photo_tags (photo_id, tag_id) VALUES (?, ?)", photoId, tagId)
            }
        }
    }

    static func splitTags(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Date helpers

    /// "yyyy-MM-dd HH:mm:ss" in the current time zone; the text form used for calendar grouping.
    static func localTimestamp(_ date: Date) -> String {
        localFormatter.string(from: date)
    }

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Row mapping

    static func mapPhoto(_ row: [Binding?]) -> PhotoFile {
        func d(_ i: Int) -> Double? {
            if let v = row[i] as? Double { return v }
            if let v = row[i] as? Int64 { return Double(v) }
            return nil
        }
        func i64(_ i: Int) -> Int64? { row[i] as? Int64 }
        func int(_ i: Int) -> Int? { (row[i] as? Int64).map { Int($0) } }
        func s(_ i: Int) -> String? { row[i] as? String }
        func date(_ i: Int) -> Date? { d(i).map { Date(timeIntervalSince1970: $0) } }

        var photo = PhotoFile(
            id: i64(0),
            rootDirectoryId: i64(1) ?? 0,
            relativePath: s(2) ?? "",
            fileName: s(3) ?? "",
            fileExtension: s(4) ?? "",
            fileSize: i64(5) ?? 0,
            fileHash: s(6) ?? "",
            createdAt: date(7) ?? Date(timeIntervalSince1970: 0),
            modifiedAt: date(8) ?? Date(timeIntervalSince1970: 0),
            exifDateTaken: date(9),
            exifCameraModel: s(10),
            exifLensModel: s(11),
            exifFocalLength: d(12),
            exifAperture: d(13),
            exifIso: int(14),
            exifShutterSpeed: s(15),
            imageWidth: int(16),
            imageHeight: int(17),
            hasThumbnail: (i64(18) ?? 0) != 0,
            thumbnailPath: s(19),
            userDescription: s(20),
            userTags: s(21),
            rating: int(22) ?? 0,
            colorTag: s(23)
        )
        photo.captureDate = date(24) ?? photo.modifiedAt
        photo.dateSource = s(25).flatMap(DateSource.init(rawValue:)) ?? .file
        photo.mediaKind = s(26).flatMap(MediaKind.init(rawValue:)) ?? .image
        photo.gpsLatitude = d(27)
        photo.gpsLongitude = d(28)
        photo.contentIdentifier = s(29)
        photo.eventId = i64(30)
        return photo
    }

    private func queryPhotos(_ sql: String, _ bindings: [Binding?] = []) throws -> [PhotoFile] {
        let statement = try conn().prepare(sql)
        return try statement.bind(bindings).map { Self.mapPhoto($0) }
    }

    // MARK: - Filters

    /// Builds a WHERE clause (without the keyword) over alias `p`.
    static func whereClause(for filter: PhotoFilter) -> (String, [Binding?]) {
        var clauses: [String] = []
        var bindings: [Binding?] = []

        if let root = filter.rootDirectoryId {
            clauses.append("p.root_directory_id = ?")
            bindings.append(root)
        }
        if let dir = filter.directoryPath {
            if filter.includeSubdirectories {
                if !dir.isEmpty {
                    clauses.append("(p.dir_path = ? OR substr(p.dir_path, 1, ?) = ?)")
                    bindings.append(contentsOf: [dir, Int64(dir.unicodeScalars.count + 1), dir + "/"] as [Binding?])
                }
            } else {
                clauses.append("p.dir_path = ?")
                bindings.append(dir)
            }
        }
        if let from = filter.captureFrom {
            clauses.append("p.capture_date >= ?")
            bindings.append(from.timeIntervalSince1970)
        }
        if let to = filter.captureTo {
            clauses.append("p.capture_date < ?")
            bindings.append(to.timeIntervalSince1970)
        }
        if let prefix = filter.capturePrefix, !prefix.isEmpty {
            clauses.append("p.capture_local >= ? AND p.capture_local < ?")
            bindings.append(contentsOf: [prefix, prefix + "~"])
        }
        if let eventId = filter.eventId {
            if filter.includeSubEvents {
                clauses.append("p.event_id IN (WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT e.id FROM events e JOIN sub ON e.parent_id = sub.id) SELECT id FROM sub)")
            } else {
                clauses.append("p.event_id = ?")
            }
            bindings.append(eventId)
        }
        if filter.unassignedOnly {
            clauses.append("p.event_id IS NULL")
        }
        if let text = filter.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            let like = "%\(text)%"
            clauses.append("""
                (p.file_name LIKE ? OR p.relative_path LIKE ? OR p.user_description LIKE ? OR p.user_tags LIKE ?
                 OR p.exif_camera_model LIKE ? OR p.exif_lens_model LIKE ?
                 OR p.id IN (SELECT pt.photo_id FROM photo_tags pt JOIN tags t ON t.id = pt.tag_id WHERE t.name LIKE ?)
                 OR p.event_id IN (SELECT id FROM events WHERE name LIKE ? OR place LIKE ?))
                """)
            bindings.append(contentsOf: Array(repeating: like, count: 9))
        }
        if let minRating = filter.minRating, minRating > 0 {
            clauses.append("p.rating >= ?")
            bindings.append(Int64(minRating))
        }
        if !filter.colorTags.isEmpty {
            clauses.append("p.color_tag IN (\(placeholders(filter.colorTags.count)))")
            bindings.append(contentsOf: filter.colorTags.sorted().map { $0 as Binding? })
        }
        for tagId in filter.tagIds.sorted() {
            clauses.append("p.id IN (SELECT photo_id FROM photo_tags WHERE tag_id = ?)")
            bindings.append(tagId)
        }
        if !filter.mediaKinds.isEmpty {
            clauses.append("p.media_kind IN (\(placeholders(filter.mediaKinds.count)))")
            bindings.append(contentsOf: filter.mediaKinds.map(\.rawValue).sorted().map { $0 as Binding? })
        }
        if !filter.dateSources.isEmpty {
            clauses.append("p.date_source IN (\(placeholders(filter.dateSources.count)))")
            bindings.append(contentsOf: filter.dateSources.map(\.rawValue).sorted().map { $0 as Binding? })
        }
        if let camera = filter.cameraModel {
            clauses.append("p.exif_camera_model = ?")
            bindings.append(camera)
        }
        if let lens = filter.lensModel {
            clauses.append("p.exif_lens_model = ?")
            bindings.append(lens)
        }
        if let hasGPS = filter.hasGPS {
            clauses.append(hasGPS ? "p.gps_lat IS NOT NULL" : "p.gps_lat IS NULL")
        }
        if filter.duplicatesOnly {
            clauses.append("p.file_hash IN (SELECT file_hash FROM photo_files GROUP BY file_hash HAVING COUNT(*) > 1)")
        }
        if let ids = filter.photoIds {
            clauses.append("p.id IN (SELECT value FROM json_each(?))")
            bindings.append(jsonArray(ids))
        }
        return (clauses.isEmpty ? "1" : clauses.joined(separator: " AND "), bindings)
    }

    static func placeholders(_ n: Int) -> String {
        Array(repeating: "?", count: n).joined(separator: ",")
    }

    static func jsonArray(_ ids: [Int64]) -> String {
        "[" + ids.map(String.init).joined(separator: ",") + "]"
    }

    private static func orderBy(_ sort: PhotoSort) -> String {
        switch sort {
        case .captureAscending: return "p.capture_date ASC, p.id ASC"
        case .captureDescending: return "p.capture_date DESC, p.id DESC"
        case .path: return "p.root_directory_id, p.relative_path"
        case .name: return "p.file_name COLLATE NOCASE, p.id"
        case .sizeDescending: return "p.file_size DESC, p.id"
        }
    }

    // MARK: - Photo queries

    func photos(matching filter: PhotoFilter, sort: PhotoSort = .captureDescending, limit: Int? = nil, offset: Int = 0) throws -> [PhotoFile] {
        let (whereSQL, bindings) = Self.whereClause(for: filter)
        var sql = "SELECT \(Self.photoColumns) FROM photo_files p WHERE \(whereSQL) ORDER BY \(Self.orderBy(sort))"
        var all = bindings
        if let limit {
            sql += " LIMIT ? OFFSET ?"
            all.append(contentsOf: [Int64(limit), Int64(offset)])
        }
        return try queryPhotos(sql, all)
    }

    func countPhotos(matching filter: PhotoFilter) throws -> (count: Int, bytes: Int64) {
        let (whereSQL, bindings) = Self.whereClause(for: filter)
        let row = try conn().prepare("SELECT COUNT(*), COALESCE(SUM(p.file_size), 0) FROM photo_files p WHERE \(whereSQL)").bind(bindings).makeIterator().next()
        return (Int(row?[0] as? Int64 ?? 0), row?[1] as? Int64 ?? 0)
    }

    func photoIds(matching filter: PhotoFilter) throws -> [Int64] {
        let (whereSQL, bindings) = Self.whereClause(for: filter)
        return try conn().prepare("SELECT p.id FROM photo_files p WHERE \(whereSQL)").bind(bindings).compactMap { $0[0] as? Int64 }
    }

    func photos(withIds ids: [Int64]) throws -> [PhotoFile] {
        guard !ids.isEmpty else { return [] }
        var filter = PhotoFilter()
        filter.photoIds = ids
        return try photos(matching: filter, sort: .captureAscending)
    }

    // MARK: - Analytics

    private static func dimensionSQL(_ dim: PivotDimension) -> (expr: String, join: String) {
        let topEventCTE = "(WITH RECURSIVE anc(id, top) AS (SELECT id, id FROM events WHERE parent_id IS NULL UNION ALL SELECT e.id, anc.top FROM events e JOIN anc ON e.parent_id = anc.id) SELECT id, top FROM anc)"
        let cellExpr = "(CAST(p.gps_lat * 10 AS INTEGER) || ',' || CAST(p.gps_lon * 10 AS INTEGER))"
        switch dim {
        case .year: return ("substr(p.capture_local, 1, 4)", "")
        case .month: return ("substr(p.capture_local, 1, 7)", "")
        case .day: return ("substr(p.capture_local, 1, 10)", "")
        case .week: return ("strftime('%Y-W%W', p.capture_local)", "")
        case .weekday: return ("strftime('%w', p.capture_local)", "")
        case .hour: return ("substr(p.capture_local, 12, 2)", "")
        case .event: return ("COALESCE(CAST(p.event_id AS TEXT), '')", "")
        case .topEvent: return ("COALESCE(CAST(te.top AS TEXT), '')", "LEFT JOIN \(topEventCTE) te ON te.id = p.event_id")
        case .person: return ("COALESCE(tp.name, '')", "LEFT JOIN (SELECT pt.photo_id, t.name FROM photo_tags pt JOIN tags t ON t.id = pt.tag_id WHERE t.kind = 'person') tp ON tp.photo_id = p.id")
        case .keyword: return ("COALESCE(tk.name, '')", "LEFT JOIN (SELECT pt.photo_id, t.name FROM photo_tags pt JOIN tags t ON t.id = pt.tag_id WHERE t.kind = 'keyword') tk ON tk.photo_id = p.id")
        case .country: return ("COALESCE(g.country, CASE WHEN p.gps_lat IS NULL THEN '' ELSE '(not looked up)' END)", "LEFT JOIN geo_cells g ON g.cell = \(cellExpr)")
        case .city: return ("COALESCE(g.locality, CASE WHEN p.gps_lat IS NULL THEN '' ELSE '(not looked up)' END)", "LEFT JOIN geo_cells g ON g.cell = \(cellExpr)")
        case .camera: return ("COALESCE(p.exif_camera_model, '')", "")
        case .lens: return ("COALESCE(p.exif_lens_model, '')", "")
        case .focalLength: return ("COALESCE(CAST(CAST(round(p.exif_focal_length) AS INTEGER) AS TEXT) || ' mm', '')", "")
        case .iso: return ("COALESCE(CAST(p.exif_iso AS TEXT), '')", "")
        case .aperture: return ("COALESCE(printf('f/%.1f', p.exif_aperture), '')", "")
        case .mediaKind: return ("p.media_kind", "")
        case .fileExtension: return ("lower(p.file_extension)", "")
        case .rating: return ("CAST(p.rating AS TEXT)", "")
        case .colorTag: return ("COALESCE(p.color_tag, '')", "")
        case .dateSource: return ("p.date_source", "")
        case .root: return ("CAST(p.root_directory_id AS TEXT)", "")
        case .directory: return ("CAST(p.root_directory_id AS TEXT) || ':' || p.dir_path", "")
        }
    }

    /// Counts and bytes grouped by one or two dimensions. An empty key means "unknown / none".
    func pivot(_ dim: PivotDimension, by dim2: PivotDimension? = nil, filter: PhotoFilter = .all, limit: Int = 5000) throws -> [PivotRow] {
        let (whereSQL, bindings) = Self.whereClause(for: filter)
        let a = Self.dimensionSQL(dim)
        let b = dim2.map(Self.dimensionSQL)
        // Each join is aliased differently, but country and city share `g`; use it once.
        var joins = [a.join]
        if let b, b.join != a.join { joins.append(b.join) }
        let keys = b.map { "\(a.expr) AS k1, \($0.expr) AS k2" } ?? "\(a.expr) AS k1, NULL AS k2"
        let sql = """
            SELECT \(keys), COUNT(*), COALESCE(SUM(p.file_size), 0)
            FROM photo_files p \(joins.joined(separator: " "))
            WHERE \(whereSQL)
            GROUP BY k1, k2
            ORDER BY k1, k2
            LIMIT \(limit)
            """
        return try conn().prepare(sql).bind(bindings).map { row in
            PivotRow(key: row[0] as? String ?? "", key2: row[1] as? String,
                     count: Int(row[2] as? Int64 ?? 0), bytes: row[3] as? Int64 ?? 0)
        }
    }

    /// Photo counts per directory of one root (for the directory sidebar).
    func directoryCounts(rootId: Int64) throws -> [(path: String, count: Int)] {
        try conn().prepare("SELECT dir_path, COUNT(*) FROM photo_files WHERE root_directory_id = ? GROUP BY dir_path ORDER BY dir_path", rootId)
            .map { ($0[0] as? String ?? "", Int($0[1] as? Int64 ?? 0)) }
    }

    func extensionCounts(rootId: Int64) throws -> [(ext: String, count: Int)] {
        try conn().prepare("SELECT lower(file_extension), COUNT(*) FROM photo_files WHERE root_directory_id = ? GROUP BY 1 ORDER BY 2 DESC", rootId)
            .map { ($0[0] as? String ?? "", Int($0[1] as? Int64 ?? 0)) }
    }

    /// Ungeocoded GPS cells (0.1° grid), most photos first.
    func pendingGeoCells(limit: Int = 200) throws -> [(cell: String, lat: Double, lon: Double, count: Int)] {
        let sql = """
            SELECT (CAST(gps_lat * 10 AS INTEGER) || ',' || CAST(gps_lon * 10 AS INTEGER)) AS cell, AVG(gps_lat), AVG(gps_lon), COUNT(*)
            FROM photo_files WHERE gps_lat IS NOT NULL
            GROUP BY cell HAVING cell NOT IN (SELECT cell FROM geo_cells)
            ORDER BY 4 DESC LIMIT ?
            """
        return try conn().prepare(sql, Int64(limit)).map {
            ($0[0] as? String ?? "", $0[1] as? Double ?? 0, $0[2] as? Double ?? 0, Int($0[3] as? Int64 ?? 0))
        }
    }

    func saveGeoCell(_ cell: String, country: String?, locality: String?, area: String?) throws {
        try conn().run("INSERT OR REPLACE INTO geo_cells (cell, country, locality, area, looked_up_at) VALUES (?, ?, ?, ?, ?)",
                       cell, country, locality, area, Date().timeIntervalSince1970)
    }

    // MARK: - Root Directory Operations

    func addRootDirectory(_ directory: RootDirectory) throws -> Int64 {
        let insert = DatabaseTables.rootDirectories.insert(
            DatabaseTables.rootDirPath <- directory.path,
            DatabaseTables.rootDirName <- directory.name,
            DatabaseTables.rootDirIsActive <- directory.isActive,
            DatabaseTables.rootDirCreatedAt <- directory.createdAt,
            DatabaseTables.rootDirBookmarkData <- directory.bookmarkData
        )
        return try conn().run(insert)
    }

    func getRootDirectories() throws -> [RootDirectory] {
        try conn().prepare(DatabaseTables.rootDirectories).map { row in
            RootDirectory(
                id: row[DatabaseTables.rootDirId],
                path: row[DatabaseTables.rootDirPath],
                name: row[DatabaseTables.rootDirName],
                isActive: row[DatabaseTables.rootDirIsActive],
                createdAt: row[DatabaseTables.rootDirCreatedAt],
                lastScannedAt: row[DatabaseTables.rootDirLastScannedAt],
                bookmarkData: row[DatabaseTables.rootDirBookmarkData]
            )
        }
    }

    func updateRootDirectoryLastScanned(_ id: Int64, date: Date) throws {
        let directory = DatabaseTables.rootDirectories.filter(DatabaseTables.rootDirId == id)
        try conn().run(directory.update(DatabaseTables.rootDirLastScannedAt <- date))
    }

    func deleteRootDirectory(_ id: Int64) throws {
        let db = try conn()
        try db.transaction {
            // Explicit, in case the database was opened somewhere without foreign keys enabled.
            try db.run("DELETE FROM photo_files WHERE root_directory_id = ?", id)
            try db.run("DELETE FROM root_directories WHERE id = ?", id)
        }
    }

    // MARK: - Scanner support

    func scanIndex(rootId: Int64) throws -> [String: IndexedFile] {
        var index: [String: IndexedFile] = [:]
        for row in try conn().prepare("SELECT relative_path, id, file_size, modified_at, file_hash FROM photo_files WHERE root_directory_id = ?", rootId) {
            guard let rel = row[0] as? String, let id = row[1] as? Int64 else { continue }
            let mtime = (row[3] as? Double) ?? (row[3] as? Int64).map(Double.init) ?? 0
            index[rel] = IndexedFile(id: id, fileSize: row[2] as? Int64 ?? -1, modifiedAt: mtime, fileHash: row[4] as? String ?? "")
        }
        return index
    }

    private static let upsertSQL = """
        INSERT INTO photo_files (
            root_directory_id, relative_path, dir_path, file_name, base_name, file_extension, media_kind,
            file_size, file_hash, created_at, modified_at, exif_date_taken, capture_date, capture_local, date_source,
            exif_camera_model, exif_lens_model, exif_focal_length, exif_aperture, exif_iso, exif_shutter_speed,
            image_width, image_height, gps_lat, gps_lon, content_id, duration)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(root_directory_id, relative_path) DO UPDATE SET
            dir_path = excluded.dir_path, file_name = excluded.file_name, base_name = excluded.base_name,
            file_extension = excluded.file_extension, media_kind = excluded.media_kind,
            file_size = excluded.file_size,
            has_thumbnail = CASE WHEN photo_files.file_hash = excluded.file_hash THEN photo_files.has_thumbnail ELSE 0 END,
            thumbnail_path = CASE WHEN photo_files.file_hash = excluded.file_hash THEN photo_files.thumbnail_path ELSE NULL END,
            file_hash = excluded.file_hash,
            created_at = excluded.created_at, modified_at = excluded.modified_at,
            exif_date_taken = excluded.exif_date_taken, capture_date = excluded.capture_date,
            capture_local = excluded.capture_local, date_source = excluded.date_source,
            exif_camera_model = excluded.exif_camera_model, exif_lens_model = excluded.exif_lens_model,
            exif_focal_length = excluded.exif_focal_length, exif_aperture = excluded.exif_aperture,
            exif_iso = excluded.exif_iso, exif_shutter_speed = excluded.exif_shutter_speed,
            image_width = excluded.image_width, image_height = excluded.image_height,
            gps_lat = excluded.gps_lat, gps_lon = excluded.gps_lon,
            content_id = excluded.content_id, duration = excluded.duration
        """

    /// Inserts or updates scanned files in one transaction. User fields are left alone.
    func upsert(_ files: [ScannedFile]) throws {
        guard !files.isEmpty else { return }
        let db = try conn()
        try db.transaction {
            let statement = try db.prepare(Self.upsertSQL)
            for f in files {
                let base = ((f.fileName as NSString).deletingPathExtension).lowercased()
                let values: [Binding?] = [
                    f.rootDirectoryId, f.relativePath, (f.relativePath as NSString).deletingLastPathComponent,
                    f.fileName, base, f.fileExtension.lowercased(), f.mediaKind.rawValue,
                    f.fileSize, f.fileHash, f.createdAt.timeIntervalSince1970, f.modifiedAt.timeIntervalSince1970,
                    f.exifDateTaken?.timeIntervalSince1970, f.captureDate.timeIntervalSince1970,
                    Self.localTimestamp(f.captureDate), f.dateSource.rawValue,
                    f.cameraModel, f.lensModel, f.focalLength, f.aperture, f.iso.map(Int64.init), f.shutterSpeed,
                    f.imageWidth.map(Int64.init), f.imageHeight.map(Int64.init), f.gpsLatitude, f.gpsLongitude,
                    f.contentIdentifier, f.duration
                ]
                try statement.run(values)
            }
        }
    }

    /// Deletes rows by id and returns the hashes that no longer have any row (their thumbnails can go).
    @discardableResult
    func deletePhotos(ids: [Int64]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let db = try conn()
        var orphanedHashes: [String] = []
        try db.transaction {
            let json = Self.jsonArray(ids)
            let hashes = try db.prepare("SELECT DISTINCT file_hash FROM photo_files WHERE id IN (SELECT value FROM json_each(?))", json)
                .compactMap { $0[0] as? String }
            try db.run("DELETE FROM photo_files WHERE id IN (SELECT value FROM json_each(?))", json)
            for hash in hashes where (try db.scalar("SELECT COUNT(*) FROM photo_files WHERE file_hash = ?", hash) as? Int64 ?? 0) == 0 {
                orphanedHashes.append(hash)
            }
        }
        return orphanedHashes
    }

    func photosNeedingThumbnails(rootId: Int64, regenerateAll: Bool) throws -> [PhotoFile] {
        var filter = PhotoFilter()
        filter.rootDirectoryId = rootId
        let (whereSQL, bindings) = Self.whereClause(for: filter)
        let extra = regenerateAll ? "" : " AND p.has_thumbnail = 0"
        // One thumbnail per content hash: copies share it.
        return try queryPhotos("""
            SELECT \(Self.photoColumns) FROM photo_files p
            WHERE \(whereSQL)\(extra)
              AND p.id = (SELECT MIN(q.id) FROM photo_files q WHERE q.file_hash = p.file_hash AND q.root_directory_id = p.root_directory_id)
            ORDER BY p.capture_date DESC
            """, bindings)
    }

    /// Marks every row with the given content hash as having this thumbnail.
    func setThumbnails(_ entries: [(hash: String, path: String)]) throws {
        guard !entries.isEmpty else { return }
        let db = try conn()
        try db.transaction {
            let statement = try db.prepare("UPDATE photo_files SET has_thumbnail = 1, thumbnail_path = ? WHERE file_hash = ?")
            for e in entries { try statement.run(e.path, e.hash) }
        }
    }

    func updateThumbnailPath(_ photoId: Int64, thumbnailPath: String) throws {
        try conn().run("UPDATE photo_files SET has_thumbnail = 1, thumbnail_path = ? WHERE id = ?", thumbnailPath, photoId)
    }

    /// Points a row at a new location after a move (same file contents).
    func relocatePhoto(_ photoId: Int64, rootId: Int64, relativePath: String) throws {
        let name = (relativePath as NSString).lastPathComponent
        try conn().run("UPDATE photo_files SET root_directory_id = ?, relative_path = ?, dir_path = ?, file_name = ?, base_name = ? WHERE id = ?",
                       rootId, relativePath, (relativePath as NSString).deletingLastPathComponent, name,
                       ((name as NSString).deletingPathExtension).lowercased(), photoId)
    }

    // MARK: - Duplicates

    /// All files whose content hash occurs more than once, in one query.
    func findDuplicates() throws -> [DuplicateGroup] {
        let rows = try queryPhotos("""
            SELECT \(Self.photoColumns) FROM photo_files p
            WHERE p.file_hash IN (SELECT file_hash FROM photo_files GROUP BY file_hash HAVING COUNT(*) > 1)
            ORDER BY p.file_hash, p.root_directory_id, p.relative_path
            """)
        var groups: [DuplicateGroup] = []
        var current: [PhotoFile] = []
        func flush() {
            guard let first = current.first else { return }
            groups.append(DuplicateGroup(fileHash: first.fileHash, files: current, totalSize: current.reduce(0) { $0 + $1.fileSize }))
            current.removeAll(keepingCapacity: true)
        }
        for photo in rows {
            if let last = current.last, last.fileHash != photo.fileHash { flush() }
            current.append(photo)
        }
        flush()
        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    /// Number of catalogue rows with this content, excluding the given ids.
    func copyCount(hash: String, excluding ids: Set<Int64> = []) throws -> Int {
        let count = try conn().scalar("SELECT COUNT(*) FROM photo_files WHERE file_hash = ? AND id NOT IN (SELECT value FROM json_each(?))",
                                      hash, Self.jsonArray(Array(ids))) as? Int64 ?? 0
        return Int(count)
    }

    private func rootPathMap() throws -> [Int64: String] {
        var map: [Int64: String] = [:]
        for row in try conn().prepare("SELECT id, path FROM root_directories") {
            if let id = row[0] as? Int64, let path = row[1] as? String { map[id] = path }
        }
        return map
    }

    /// Directories containing duplicated files. Built from the duplicate rows plus per-directory totals,
    /// never the whole table.
    func findDuplicatesByDirectory(groups: [DuplicateGroup]? = nil) throws -> [DirectoryDuplicateInfo] {
        let groups = try groups ?? findDuplicates()
        let roots = try rootPathMap()

        var totals: [String: (count: Int, size: Int64)] = [:]
        for row in try conn().prepare("SELECT root_directory_id, dir_path, COUNT(*), SUM(file_size) FROM photo_files GROUP BY root_directory_id, dir_path") {
            let key = "\(row[0] as? Int64 ?? 0):\(row[1] as? String ?? "")"
            totals[key] = (Int(row[2] as? Int64 ?? 0), row[3] as? Int64 ?? 0)
        }

        var byDir: [String: [PhotoFile]] = [:]
        for group in groups {
            for file in group.files {
                byDir["\(file.rootDirectoryId):\(file.directoryPath)", default: []].append(file)
            }
        }

        return byDir.map { key, files in
            let first = files[0]
            let total = totals[key] ?? (files.count, files.reduce(0) { $0 + $1.fileSize })
            let fullPath = ((roots[first.rootDirectoryId] ?? "") as NSString).appendingPathComponent(first.directoryPath)
            return DirectoryDuplicateInfo(
                directoryPath: first.directoryPath,
                fullPath: fullPath,
                fileCount: total.count,
                duplicateFileCount: files.count,
                totalSize: total.size,
                wastedSize: files.reduce(0) { $0 + $1.fileSize },
                files: files,
                rootDirectoryId: first.rootDirectoryId
            )
        }
        .sorted { $0.duplicateFileCount > $1.duplicateFileCount }
    }

    /// Directories whose direct files are exactly the same set of contents. Only directories made
    /// entirely of duplicated files can qualify, so only those are loaded.
    func findCompleteDuplicateDirectories() throws -> [CompleteDuplicateDirectory] {
        let roots = try rootPathMap()
        let signatureSQL = """
            SELECT root_directory_id, dir_path, COUNT(*), SUM(file_size), group_concat(file_hash, ',')
            FROM (SELECT root_directory_id, dir_path, file_size, file_hash FROM photo_files
                  ORDER BY root_directory_id, dir_path, file_hash)
            GROUP BY root_directory_id, dir_path
            HAVING COUNT(*) = SUM(CASE WHEN file_hash IN (SELECT file_hash FROM photo_files GROUP BY file_hash HAVING COUNT(*) > 1) THEN 1 ELSE 0 END)
            """
        var bySignature: [String: [(root: Int64, dir: String, count: Int, size: Int64)]] = [:]
        for row in try conn().prepare(signatureSQL) {
            guard let root = row[0] as? Int64, let dir = row[1] as? String, let sig = row[4] as? String else { continue }
            // A set comparison: collapse repeated hashes within the directory.
            let signature = Array(Set(sig.split(separator: ","))).sorted().joined(separator: ",")
            bySignature[signature, default: []].append((root, dir, Int(row[2] as? Int64 ?? 0), row[3] as? Int64 ?? 0))
        }

        var results: [CompleteDuplicateDirectory] = []
        for (_, dirs) in bySignature where dirs.count > 1 {
            let infos: [DirectoryInfo] = try dirs.map { d in
                var filter = PhotoFilter()
                filter.rootDirectoryId = d.root
                filter.directoryPath = d.dir
                let files = try photos(matching: filter, sort: .name)
                return DirectoryInfo(relativePath: d.dir,
                                     fullPath: ((roots[d.root] ?? "") as NSString).appendingPathComponent(d.dir),
                                     files: files, rootDirectoryId: d.root)
            }
            .sorted { $0.fullPath < $1.fullPath }
            // A directory nested inside its twin would be removed with it; keep such pairs out.
            let nonNested = infos.filter { info in
                !infos.contains { other in other.fullPath != info.fullPath && info.fullPath.hasPrefix(other.fullPath + "/") }
            }
            guard nonNested.count > 1 else { continue }
            results.append(CompleteDuplicateDirectory(
                primaryDirectory: nonNested[0],
                duplicateDirectories: Array(nonNested.dropFirst()),
                fileCount: nonNested[0].files.count,
                totalSize: nonNested[0].files.reduce(0) { $0 + $1.fileSize }
            ))
        }
        return results.sorted { $0.fileCount > $1.fileCount }
    }

    // MARK: - Photo File Operations (compatibility API used by the views)

    func getPhotosForDirectory(_ directoryId: Int64) throws -> [PhotoFile] {
        var filter = PhotoFilter()
        filter.rootDirectoryId = directoryId
        return try photos(matching: filter, sort: .path)
    }

    func deletePhotosInDirectory(_ directoryPath: String, rootId: Int64) throws -> Int {
        let db = try conn()
        try db.run("DELETE FROM photo_files WHERE root_directory_id = ? AND dir_path = ?", rootId, directoryPath)
        return db.changes
    }

    func deletePhoto(_ photoId: Int64) throws {
        try deletePhotos(ids: [photoId])
    }

    func clearPhotosForDirectory(_ directoryId: Int64) throws {
        try conn().run("DELETE FROM photo_files WHERE root_directory_id = ?", directoryId)
    }

    func getPhotoById(_ photoId: Int64) throws -> PhotoFile? {
        try queryPhotos("SELECT \(Self.photoColumns) FROM photo_files p WHERE p.id = ?", [photoId]).first
    }

    func updatePhotoMetadata(_ photoId: Int64, description: String?, tags: String?) throws {
        let db = try conn()
        try db.transaction {
            try db.run("UPDATE photo_files SET user_description = ?, user_tags = ? WHERE id = ?", description, tags, photoId)
            // Keep the structured keyword tags in step with the free-text field.
            try db.run("DELETE FROM photo_tags WHERE photo_id = ? AND tag_id IN (SELECT id FROM tags WHERE kind = 'keyword')", photoId)
            for name in Self.splitTags(tags ?? "") {
                let tagId = try tagId(named: name, kind: .keyword, db: db)
                try db.run("INSERT OR IGNORE INTO photo_tags (photo_id, tag_id) VALUES (?, ?)", photoId, tagId)
            }
        }
    }

    func updatePhotoRating(_ photoId: Int64, rating: Int) throws {
        try updateRating(photoIds: [photoId], rating: rating)
    }

    func updateRating(photoIds: [Int64], rating: Int) throws {
        try conn().run("UPDATE photo_files SET rating = ? WHERE id IN (SELECT value FROM json_each(?))",
                       Int64(min(max(rating, 0), 5)), Self.jsonArray(photoIds))
    }

    func updatePhotoColorTag(_ photoId: Int64, colorTag: String?) throws {
        try updateColorTag(photoIds: [photoId], colorTag: colorTag)
    }

    func updateColorTag(photoIds: [Int64], colorTag: String?) throws {
        try conn().run("UPDATE photo_files SET color_tag = ? WHERE id IN (SELECT value FROM json_each(?))",
                       colorTag, Self.jsonArray(photoIds))
    }

    func searchPhotos(query: String, minRating: Int? = nil, colorTag: String? = nil, limit: Int? = 5000) throws -> [PhotoFile] {
        var filter = PhotoFilter()
        filter.text = query
        filter.minRating = minRating
        if let colorTag { filter.colorTags = [colorTag] }
        return try photos(matching: filter, limit: limit)
    }

    func getPhotosByRating(minRating: Int) throws -> [PhotoFile] {
        var filter = PhotoFilter()
        filter.minRating = minRating
        return try photos(matching: filter)
    }

    func getPhotosByColorTag(_ colorTag: String) throws -> [PhotoFile] {
        var filter = PhotoFilter()
        filter.colorTags = [colorTag]
        return try photos(matching: filter)
    }

    // MARK: - Events

    func createEvent(name: String, parentId: Int64?, kind: String = "event", place: String? = nil) throws -> Int64 {
        let db = try conn()
        try db.run("INSERT INTO events (parent_id, name, kind, place, created_at) VALUES (?, ?, ?, ?, ?)",
                   parentId, name, kind, place, Date().timeIntervalSince1970)
        return db.lastInsertRowid
    }

    func updateEvent(_ id: Int64, name: String, kind: String, place: String?, notes: String?) throws {
        try conn().run("UPDATE events SET name = ?, kind = ?, place = ?, notes = ? WHERE id = ?", name, kind, place, notes, id)
    }

    func moveEvent(_ id: Int64, toParent parentId: Int64?) throws {
        if let parentId {
            // Refuse to make an event its own ancestor.
            let isDescendant = try conn().scalar("""
                WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT e.id FROM events e JOIN sub ON e.parent_id = sub.id)
                SELECT COUNT(*) FROM sub WHERE id = ?
                """, id, parentId) as? Int64 ?? 0
            guard isDescendant == 0 else { throw DatabaseError.queryFailed("Cannot move an event inside itself") }
        }
        try conn().run("UPDATE events SET parent_id = ? WHERE id = ?", parentId, id)
    }

    /// Deletes an event and its sub-events. Their photos become unassigned.
    func deleteEvent(_ id: Int64) throws {
        let db = try conn()
        try db.transaction {
            try db.run("""
                UPDATE photo_files SET event_id = NULL WHERE event_id IN (
                    WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT e.id FROM events e JOIN sub ON e.parent_id = sub.id)
                    SELECT id FROM sub)
                """, id)
            try db.run("DELETE FROM events WHERE id = ?", id)
        }
    }

    /// Assigns photos to an event (nil unassigns).
    func assignPhotos(_ photoIds: [Int64], toEvent eventId: Int64?) throws {
        guard !photoIds.isEmpty else { return }
        try conn().run("UPDATE photo_files SET event_id = ? WHERE id IN (SELECT value FROM json_each(?))", eventId, Self.jsonArray(photoIds))
    }

    /// All events with photo counts and date ranges rolled up from their sub-events.
    func events() throws -> [PhotoEvent] {
        let db = try conn()
        var events: [Int64: PhotoEvent] = [:]
        for row in try db.prepare("SELECT id, parent_id, name, kind, place, notes FROM events") {
            guard let id = row[0] as? Int64 else { continue }
            events[id] = PhotoEvent(id: id, parentId: row[1] as? Int64, name: row[2] as? String ?? "",
                                    kind: row[3] as? String ?? "event", place: row[4] as? String, notes: row[5] as? String)
        }
        for row in try db.prepare("SELECT event_id, COUNT(*), MIN(capture_date), MAX(capture_date) FROM photo_files WHERE event_id IS NOT NULL GROUP BY event_id") {
            guard let id = row[0] as? Int64 else { continue }
            let count = Int(row[1] as? Int64 ?? 0)
            let start = (row[2] as? Double).map(Date.init(timeIntervalSince1970:))
            let end = (row[3] as? Double).map(Date.init(timeIntervalSince1970:))
            // Roll up to every ancestor.
            var cursor: Int64? = id
            var guardCount = 0
            while let current = cursor, var event = events[current], guardCount < 64 {
                event.photoCount += count
                if let start { event.startDate = min(event.startDate ?? start, start) }
                if let end { event.endDate = max(event.endDate ?? end, end) }
                events[current] = event
                cursor = event.parentId
                guardCount += 1
            }
        }
        return events.values.sorted { ($0.startDate ?? .distantFuture, $0.name) < ($1.startDate ?? .distantFuture, $1.name) }
    }

    /// Names from the root down to this event, e.g. ["Asia Trip", "Hong Kong", "Temples"].
    func eventPath(_ id: Int64, events: [Int64: PhotoEvent]) -> [PhotoEvent] {
        var path: [PhotoEvent] = []
        var cursor: Int64? = id
        while let current = cursor, let event = events[current], path.count < 64 {
            path.insert(event, at: 0)
            cursor = event.parentId
        }
        return path
    }

    // MARK: - Tags

    private func tagId(named name: String, kind: TagKind, db: Connection) throws -> Int64 {
        if let id = try db.scalar("SELECT id FROM tags WHERE name = ? COLLATE NOCASE AND kind = ?", name, kind.rawValue) as? Int64 {
            return id
        }
        try db.run("INSERT INTO tags (name, kind) VALUES (?, ?)", name, kind.rawValue)
        return db.lastInsertRowid
    }

    func tagId(named name: String, kind: TagKind) throws -> Int64 {
        try tagId(named: name, kind: kind, db: try conn())
    }

    func tags(kind: TagKind? = nil) throws -> [PhotoTag] {
        var sql = "SELECT t.id, t.name, t.kind, COUNT(pt.photo_id) FROM tags t LEFT JOIN photo_tags pt ON pt.tag_id = t.id"
        var bindings: [Binding?] = []
        if let kind { sql += " WHERE t.kind = ?"; bindings.append(kind.rawValue) }
        sql += " GROUP BY t.id ORDER BY t.name COLLATE NOCASE"
        return try conn().prepare(sql).bind(bindings).compactMap { row in
            guard let id = row[0] as? Int64, let name = row[1] as? String else { return nil }
            return PhotoTag(id: id, name: name, kind: TagKind(rawValue: row[2] as? String ?? "") ?? .keyword,
                            photoCount: Int(row[3] as? Int64 ?? 0))
        }
    }

    func addTag(_ tagId: Int64, to photoIds: [Int64]) throws {
        try conn().run("INSERT OR IGNORE INTO photo_tags (photo_id, tag_id) SELECT value, ? FROM json_each(?)", tagId, Self.jsonArray(photoIds))
    }

    func removeTag(_ tagId: Int64, from photoIds: [Int64]) throws {
        try conn().run("DELETE FROM photo_tags WHERE tag_id = ? AND photo_id IN (SELECT value FROM json_each(?))", tagId, Self.jsonArray(photoIds))
    }

    func tags(forPhoto photoId: Int64) throws -> [PhotoTag] {
        try conn().prepare("SELECT t.id, t.name, t.kind FROM tags t JOIN photo_tags pt ON pt.tag_id = t.id WHERE pt.photo_id = ? ORDER BY t.kind, t.name", photoId)
            .compactMap { row in
                guard let id = row[0] as? Int64, let name = row[1] as? String else { return nil }
                return PhotoTag(id: id, name: name, kind: TagKind(rawValue: row[2] as? String ?? "") ?? .keyword)
            }
    }

    // MARK: - Organise plans

    struct PlanItemRecord {
        var id: Int64 = 0
        let photoId: Int64?
        let sourcePath: String
        let destRelativePath: String?
        let action: String       // copy | skip
        let reason: String?
        let fileHash: String
        let bytes: Int64
        var status: String = "pending"
        var error: String? = nil
    }

    func savePlan(targetRoot: String, summary: String, items: [PlanItemRecord]) throws -> Int64 {
        let db = try conn()
        var planId: Int64 = 0
        try db.transaction {
            try db.run("INSERT INTO org_plans (created_at, target_root, status, summary) VALUES (?, ?, 'draft', ?)",
                       Date().timeIntervalSince1970, targetRoot, summary)
            planId = db.lastInsertRowid
            let statement = try db.prepare("INSERT INTO org_plan_items (plan_id, photo_id, source_path, dest_rel_path, action, reason, file_hash, bytes) VALUES (?,?,?,?,?,?,?,?)")
            for item in items {
                try statement.run(planId, item.photoId, item.sourcePath, item.destRelativePath, item.action, item.reason, item.fileHash, item.bytes)
            }
        }
        return planId
    }

    func planItems(_ planId: Int64, status: String? = nil) throws -> [PlanItemRecord] {
        var sql = "SELECT id, photo_id, source_path, dest_rel_path, action, reason, file_hash, bytes, status, error FROM org_plan_items WHERE plan_id = ?"
        var bindings: [Binding?] = [planId]
        if let status { sql += " AND status = ?"; bindings.append(status) }
        sql += " ORDER BY id"
        return try conn().prepare(sql).bind(bindings).map { row in
            PlanItemRecord(id: row[0] as? Int64 ?? 0, photoId: row[1] as? Int64, sourcePath: row[2] as? String ?? "",
                           destRelativePath: row[3] as? String, action: row[4] as? String ?? "skip", reason: row[5] as? String,
                           fileHash: row[6] as? String ?? "", bytes: row[7] as? Int64 ?? 0,
                           status: row[8] as? String ?? "pending", error: row[9] as? String)
        }
    }

    func updatePlanItems(_ updates: [(id: Int64, status: String, error: String?)]) throws {
        guard !updates.isEmpty else { return }
        let db = try conn()
        try db.transaction {
            let statement = try db.prepare("UPDATE org_plan_items SET status = ?, error = ? WHERE id = ?")
            for u in updates { try statement.run(u.status, u.error, u.id) }
        }
    }

    func setPlanStatus(_ planId: Int64, _ status: String) throws {
        try conn().run("UPDATE org_plans SET status = ? WHERE id = ?", status, planId)
    }

    func plans() throws -> [(id: Int64, createdAt: Date, targetRoot: String, status: String, summary: String)] {
        try conn().prepare("SELECT id, created_at, target_root, status, COALESCE(summary, '') FROM org_plans ORDER BY id DESC").map {
            ($0[0] as? Int64 ?? 0, Date(timeIntervalSince1970: $0[1] as? Double ?? 0), $0[2] as? String ?? "",
             $0[3] as? String ?? "", $0[4] as? String ?? "")
        }
    }

    func rawRows(_ sql: String, _ bindings: [Binding?] = []) throws -> [[Binding?]] {
        try conn().prepare(sql).bind(bindings).map { $0 }
    }
    
    // MARK: - Debug Operations

    func executeRawSQL(_ sql: String) async throws -> ([String], [[String: String]]) {
        return try await Task.detached {
            guard let db = self.db else { throw DatabaseError.connectionFailed }
            let statement = try db.prepare(sql)
            let columnNames = statement.columnNames
            var results: [[String: String]] = []
            for row in statement {
                var rowDict: [String: String] = [:]
                for (index, columnName) in columnNames.enumerated() {
                    let value: String
                    switch row[index] {
                    case nil: value = "NULL"
                    case let v as String: value = v
                    case let v as Int64: value = String(v)
                    case let v as Double: value = String(v)
                    case let v as Blob: value = "<Data: \(v.bytes.count) bytes>"
                    case let v?: value = String(describing: v)
                    }
                    rowDict[columnName] = value
                }
                results.append(rowDict)
            }
            return (columnNames, results)
        }.value
    }
}

enum DatabaseError: Error, LocalizedError {
    case connectionFailed
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "No database connection"
        case .queryFailed(let message): return message
        }
    }
}
