import Foundation

// MARK: - Shots

/// Everything that represents one moment: a RAW+JPEG pair, a Live Photo still and its video, plus every
/// byte-identical copy of those files found anywhere in the library.
struct Shot: Identifiable, Hashable {
    let id: String
    /// One file per distinct content (the copy chosen to keep), e.g. [IMG_1.CR2, IMG_1.JPG].
    var keepers: [PhotoFile]
    /// Byte-identical copies of the keepers that the plan will skip.
    var duplicates: [PhotoFile]
    let captureDate: Date
    let reliableDate: Bool
    let camera: String?
    let latitude: Double?
    let longitude: Double?

    /// Every catalogue row in the shot (used when assigning events).
    var allFiles: [PhotoFile] { keepers + duplicates }

    /// The file to show for the shot: a JPEG/HEIC rather than the RAW or video.
    var primary: PhotoFile {
        keepers.first { $0.mediaKind == .image } ?? keepers.first { $0.mediaKind == .raw } ?? keepers[0]
    }

    /// Same kind, different bytes within one shot: a re-encoded, resized or edited copy.
    var nearDuplicateKinds: [MediaKind] {
        Dictionary(grouping: keepers, by: \.mediaKind).filter { $0.value.count > 1 }.map(\.key)
    }
    var hasNearDuplicates: Bool { !nearDuplicateKinds.isEmpty }

    var hasGPS: Bool { latitude != nil }

    static func == (lhs: Shot, rhs: Shot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DuplicateStats {
    var files = 0
    var uniqueContents = 0
    var duplicateFiles = 0
    var duplicateBytes: Int64 = 0
    var shots = 0
    var rawJpegPairs = 0
    var livePhotos = 0
    var nearDuplicateShots = 0
    var undatedShots = 0
}

// MARK: - Clusters

/// A run of shots close together in time: a session (hours) or a trip (several days of sessions).
struct ShotCluster: Identifiable, Hashable {
    enum Kind: String { case session, trip, undated }

    let id: String
    let kind: Kind
    var shots: [Shot]
    var children: [ShotCluster] = []
    /// Most common place among shots with GPS, once looked up.
    var place: String?
    var places: [String] = []

    var start: Date { shots.first?.captureDate ?? .distantPast }
    var end: Date { shots.last?.captureDate ?? .distantPast }
    var fileCount: Int { shots.reduce(0) { $0 + $1.keepers.count } }
    var cameras: [String] { Array(Set(shots.compactMap(\.camera))).sorted() }
    var photoIds: [Int64] { shots.flatMap { $0.allFiles.compactMap(\.id) } }
    var days: Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
    }

    /// Events the shots are already assigned to, with counts.
    var assignedEvents: [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for shot in shots { if let e = shot.primary.eventId { counts[e, default: 0] += 1 } }
        return counts
    }

    var unassignedCount: Int { shots.filter { $0.primary.eventId == nil }.count }

    static func == (lhs: ShotCluster, rhs: ShotCluster) -> Bool { lhs.id == rhs.id && lhs.shots.count == rhs.shots.count }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ClusterSettings: Equatable {
    /// A gap longer than this starts a new session.
    var sessionGap: TimeInterval = 3 * 3600
    /// Sessions closer than this belong to the same trip (allows a day without photos).
    var tripGap: TimeInterval = 36 * 3600
    /// A run of sessions becomes a trip when at least this many calendar days each have
    /// `minShotsPerTripDay` shots, so a few everyday snaps on consecutive days don't count.
    var minTripDays = 2
    var minShotsPerTripDay = 8
    /// Consecutive sessions further apart than this (km, when both have GPS) start a new session.
    var splitDistanceKm: Double = 100
}

/// Pure functions that turn catalogue rows into shots, clusters and a copy plan. No I/O.
enum OrganizeEngine {

    // MARK: Shots

    /// Suffixes that copy tools add: Finder "IMG_1 copy", "IMG_1 copy 2", "IMG_1 2"; Windows
    /// "IMG_1 - Copy", "IMG_1 (2)". Camera burst suffixes (-1, _1) are left alone.
    static func normalizedBaseName(_ name: String) -> String {
        var base = ((name as NSString).deletingPathExtension).lowercased()
        let patterns = [#"\s+-\s+copy(\s*\(\d+\))?$"#, #"\s+copy(\s+\d+)?$"#, #"\s*\(\d+\)$"#, #"\s+\d$"#]
        var changed = true
        while changed {
            changed = false
            for p in patterns {
                if let r = base.range(of: p, options: .regularExpression), r.lowerBound != base.startIndex {
                    base.removeSubrange(r)
                    changed = true
                }
            }
        }
        return base
    }

    /// Lower is better: which of several byte-identical copies to keep.
    static func copyPreference(_ f: PhotoFile) -> (Int, Double, Int, String) {
        let path = f.relativePath.lowercased()
        let copyHints = ["copy", "backup", "dupl", "(1)", "(2)", "old", "tmp", "export"]
        let looksLikeCopy = copyHints.contains { path.contains($0) } ? 1 : 0
        return (looksLikeCopy, f.modifiedAt.timeIntervalSince1970, f.relativePath.count, f.relativePath)
    }

    static func buildShots(_ photos: [PhotoFile]) -> (shots: [Shot], stats: DuplicateStats) {
        var stats = DuplicateStats()
        stats.files = photos.count

        // 1. Collapse byte-identical copies.
        let byHash = Dictionary(grouping: photos, by: \.fileHash)
        stats.uniqueContents = byHash.count
        var keeperByHash: [String: PhotoFile] = [:]
        var copiesByHash: [String: [PhotoFile]] = [:]
        for (hash, files) in byHash {
            let sorted = files.sorted { copyPreference($0) < copyPreference($1) }
            keeperByHash[hash] = sorted[0]
            copiesByHash[hash] = Array(sorted.dropFirst())
            stats.duplicateFiles += sorted.count - 1
            stats.duplicateBytes += sorted.dropFirst().reduce(0) { $0 + $1.fileSize }
        }

        // 2. Pair distinct contents into shots: Live Photo content id first, then same (normalised) name
        //    taken within a couple of seconds.
        var groups: [[PhotoFile]] = []
        var remaining: [PhotoFile] = []
        let withContentId = Dictionary(grouping: keeperByHash.values.filter { $0.contentIdentifier != nil }, by: { $0.contentIdentifier! })
        for (_, files) in withContentId { groups.append(files) }
        remaining = keeperByHash.values.filter { $0.contentIdentifier == nil }

        let byBase = Dictionary(grouping: remaining) { normalizedBaseName($0.fileName) }
        for (_, files) in byBase {
            // Card rollover reuses names (IMG_0001 every 10,000 shots), so split by time.
            let sorted = files.sorted { $0.captureDate < $1.captureDate }
            var current: [PhotoFile] = []
            for file in sorted {
                if let last = current.last {
                    let tolerance: TimeInterval = (file.mediaKind == .video || last.mediaKind == .video) ? 3 : 2
                    let sameCamera = file.exifCameraModel == nil || last.exifCameraModel == nil || file.exifCameraModel == last.exifCameraModel
                    if file.captureDate.timeIntervalSince(last.captureDate) <= tolerance && sameCamera {
                        current.append(file)
                        continue
                    }
                    groups.append(current)
                    current = []
                }
                current.append(file)
            }
            if !current.isEmpty { groups.append(current) }
        }

        // 3. Shot records.
        var shots: [Shot] = []
        shots.reserveCapacity(groups.count)
        for files in groups {
            let keepers = files.sorted { kindOrder($0.mediaKind) < kindOrder($1.mediaKind) || (kindOrder($0.mediaKind) == kindOrder($1.mediaKind) && pixelCount($0) > pixelCount($1)) }
            let duplicates = keepers.flatMap { copiesByHash[$0.fileHash] ?? [] }
            let reliable = keepers.contains { $0.dateSource != .file }
            let dated = keepers.first { $0.dateSource != .file } ?? keepers[0]
            let gps = keepers.first { $0.gpsLatitude != nil }
            let shot = Shot(id: keepers.map(\.fileHash).sorted().joined(separator: "+"),
                            keepers: keepers, duplicates: duplicates,
                            captureDate: dated.captureDate, reliableDate: reliable,
                            camera: keepers.compactMap(\.exifCameraModel).first,
                            latitude: gps?.gpsLatitude, longitude: gps?.gpsLongitude)
            let kinds = Set(keepers.map(\.mediaKind))
            if kinds.contains(.raw) && kinds.contains(.image) { stats.rawJpegPairs += 1 }
            if kinds.contains(.video) && kinds.contains(.image) { stats.livePhotos += 1 }
            if shot.hasNearDuplicates { stats.nearDuplicateShots += 1 }
            if !reliable { stats.undatedShots += 1 }
            shots.append(shot)
        }
        shots.sort { ($0.captureDate, $0.id) < ($1.captureDate, $1.id) }
        stats.shots = shots.count
        return (shots, stats)
    }

    private static func kindOrder(_ kind: MediaKind) -> Int {
        switch kind { case .image: return 0; case .raw: return 1; case .video: return 2 }
    }

    private static func pixelCount(_ f: PhotoFile) -> Int {
        (f.imageWidth ?? 0) * (f.imageHeight ?? 0) + Int(f.fileSize / 1000)
    }

    // MARK: Clusters

    static func distanceKm(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6371.0
        let dLat = (b.0 - a.0) * .pi / 180, dLon = (b.1 - a.1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.0 * .pi / 180) * cos(b.0 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Sessions split on time gaps and big location jumps; runs of nearby sessions over several days
    /// become trips with the sessions as children. Shots without a trustworthy date go in one
    /// undated cluster per original folder.
    static func cluster(_ shots: [Shot], settings: ClusterSettings = ClusterSettings(),
                        placeName: (Shot) -> String? = { _ in nil }) -> [ShotCluster] {
        let dated = shots.filter(\.reliableDate)
        let undated = shots.filter { !$0.reliableDate }

        var sessions: [ShotCluster] = []
        var current: [Shot] = []
        var lastGPS: (Double, Double)?
        func closeSession() {
            guard let first = current.first else { return }
            sessions.append(ShotCluster(id: "s-\(first.id.prefix(16))-\(Int(first.captureDate.timeIntervalSince1970))", kind: .session, shots: current))
            current = []
            lastGPS = nil
        }
        for shot in dated {
            if let last = current.last {
                var split = shot.captureDate.timeIntervalSince(last.captureDate) > settings.sessionGap
                if !split, let here = shot.latitude.flatMap({ lat in shot.longitude.map { (lat, $0) } }), let prev = lastGPS,
                   distanceKm(prev, here) > settings.splitDistanceKm {
                    split = true
                }
                if split { closeSession() }
            }
            current.append(shot)
            if let lat = shot.latitude, let lon = shot.longitude { lastGPS = (lat, lon) }
        }
        closeSession()

        // Group sessions into trips.
        var result: [ShotCluster] = []
        var run: [ShotCluster] = []
        func closeRun() {
            guard !run.isEmpty else { return }
            let cal = Calendar.current
            let shotsPerDay = Dictionary(grouping: run.flatMap(\.shots)) { cal.startOfDay(for: $0.captureDate) }.mapValues(\.count)
            func day(_ s: ShotCluster) -> Date { cal.startOfDay(for: s.start) }
            func isBusy(_ s: ShotCluster) -> Bool { (shotsPerDay[day(s)] ?? 0) >= settings.minShotsPerTripDay }
            
            // Trips are built from busy days at most one quiet day apart; a few snaps at home before or
            // after, or a separate one-day event nearby, stay outside.
            var segments: [[Int]] = []
            for i in run.indices where isBusy(run[i]) {
                if let lastIndex = segments.last?.last,
                   (cal.dateComponents([.day], from: day(run[lastIndex]), to: day(run[i])).day ?? 99) <= 2 {
                    segments[segments.count - 1].append(i)
                } else {
                    segments.append([i])
                }
            }
            var tripRanges: [ClosedRange<Int>] = []
            for segment in segments {
                let busyDays = Set(segment.map { day(run[$0]) }).count
                if busyDays >= settings.minTripDays, let first = segment.first, let last = segment.last, last > first {
                    tripRanges.append(first...last)
                }
            }
            var i = 0
            while i < run.count {
                if let range = tripRanges.first(where: { $0.lowerBound == i }) {
                    let children = Array(run[range])
                    result.append(ShotCluster(id: "t-" + children[0].id, kind: .trip, shots: children.flatMap(\.shots), children: children))
                    i = range.upperBound + 1
                } else {
                    result.append(run[i])
                    i += 1
                }
            }
            run = []
        }
        for session in sessions {
            if let last = run.last, session.start.timeIntervalSince(last.end) > settings.tripGap {
                closeRun()
            }
            run.append(session)
        }
        closeRun()

        let undatedByFolder = Dictionary(grouping: undated) { $0.primary.directoryPath }
        for (folder, group) in undatedByFolder.sorted(by: { $0.key < $1.key }) {
            result.append(ShotCluster(id: "u-\(folder)", kind: .undated, shots: group.sorted { $0.primary.relativePath < $1.primary.relativePath },
                                      place: folder.isEmpty ? "(library root)" : folder))
        }

        return result.map { annotatePlaces($0, placeName: placeName) }
    }

    private static func annotatePlaces(_ cluster: ShotCluster, placeName: (Shot) -> String?) -> ShotCluster {
        guard cluster.kind != .undated else { return cluster }
        var c = cluster
        c.children = c.children.map { annotatePlaces($0, placeName: placeName) }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for shot in c.shots {
            guard let name = placeName(shot) else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        c.place = counts.max { $0.value < $1.value }?.key
        c.places = order
        return c
    }

    /// A suggested name: "Hong Kong, Tokyo · Mar 12–20 2019" or "Tue 12 Mar 2019".
    static func suggestedName(for cluster: ShotCluster) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        if cluster.kind == .undated { return cluster.place ?? "Undated" }
        let range: String
        if cluster.days <= 1 {
            f.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
            range = f.string(from: cluster.start)
        } else {
            let di = DateIntervalFormatter()
            di.dateTemplate = "d MMM yyyy"
            range = di.string(from: cluster.start, to: cluster.end)
        }
        let places = cluster.places.prefix(3).joined(separator: ", ")
        return places.isEmpty ? range : "\(places) · \(range)"
    }

    // MARK: Plan

    struct LayoutOptions: Equatable {
        /// For shots with several near-identical versions of one kind: keep only the best one.
        var keepBestNearDuplicate = false
        /// Per-shot override of the above (shot id → keep best).
        var nearDuplicateDecisions: [String: Bool] = [:]
        var rawFolderName = "RAW"
        var unsortedSuffix = "Unsorted"
        var undatedFolder = "Undated"
    }

    struct PlanEntry: Hashable {
        enum Action: String { case copy, skip }
        let photo: PhotoFile
        let action: Action
        /// Relative to the target root; nil for skipped files.
        let destination: String?
        let reason: String
    }

    struct PlanSummary {
        var copyFiles = 0
        var copyBytes: Int64 = 0
        var skippedDuplicates = 0
        var skippedNearDuplicates = 0
        var skippedBytes: Int64 = 0
        var folders = 0
        var unsortedFiles = 0
        var undatedFiles = 0

        var text: String {
            let b = ByteCountFormatter()
            return "\(copyFiles) files (\(b.string(fromByteCount: copyBytes))) into \(folders) folders; skipping \(skippedDuplicates) exact duplicates and \(skippedNearDuplicates) near-duplicates (\(b.string(fromByteCount: skippedBytes))); \(unsortedFiles) unsorted, \(undatedFiles) undated"
        }
    }

    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        let cleaned = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let noDots = cleaned.hasPrefix(".") ? "_" + cleaned.dropFirst() : cleaned
        return noDots.isEmpty ? "Untitled" : String(noDots.prefix(120))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Folder (relative to the target) for a shot: YYYY/YYYY-MM-DD Event/Sub/Sub, YYYY/YYYY-MM Unsorted,
    /// or Undated/<original folder>.
    static func folder(for shot: Shot, events: [Int64: PhotoEvent], options: LayoutOptions) -> (path: String, category: String) {
        if let eventId = shot.primary.eventId ?? shot.allFiles.compactMap(\.eventId).first, events[eventId] != nil {
            var chain: [PhotoEvent] = []
            var cursor: Int64? = eventId
            while let id = cursor, let e = events[id], chain.count < 32 {
                chain.insert(e, at: 0)
                cursor = e.parentId
            }
            let top = chain[0]
            let start = top.startDate ?? shot.captureDate
            let day = dayFormatter.string(from: start)
            var parts = [String(day.prefix(4)), "\(day) \(sanitize(top.name))"]
            parts.append(contentsOf: chain.dropFirst().map { sanitize($0.name) })
            return (parts.joined(separator: "/"), "event")
        }
        if shot.reliableDate {
            let day = dayFormatter.string(from: shot.captureDate)
            return ("\(day.prefix(4))/\(day.prefix(7)) \(options.unsortedSuffix)", "unsorted")
        }
        let original = (shot.primary.directoryPath as NSString).lastPathComponent
        return ("\(options.undatedFolder)/\(original.isEmpty ? "Library root" : sanitize(original))", "undated")
    }

    static func buildPlan(shots: [Shot], events: [PhotoEvent], options: LayoutOptions = LayoutOptions()) -> (entries: [PlanEntry], summary: PlanSummary) {
        let eventMap = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        var entries: [PlanEntry] = []
        var summary = PlanSummary()
        var usedNames: [String: Set<String>] = [:]   // folder → lowercased file names

        for shot in shots {
            let (folder, category) = folder(for: shot, events: eventMap, options: options)

            // Decide which distinct contents to copy.
            var toCopy: [PhotoFile] = []
            let keepBest = options.nearDuplicateDecisions[shot.id] ?? options.keepBestNearDuplicate
            for (_, files) in Dictionary(grouping: shot.keepers, by: \.mediaKind) {
                let ranked = files.sorted { pixelCount($0) > pixelCount($1) }
                if keepBest && ranked.count > 1 {
                    toCopy.append(ranked[0])
                    for other in ranked.dropFirst() {
                        entries.append(PlanEntry(photo: other, action: .skip, destination: nil,
                                                 reason: "near-duplicate of \(ranked[0].relativePath)"))
                        summary.skippedNearDuplicates += 1
                        summary.skippedBytes += other.fileSize
                    }
                } else {
                    toCopy.append(contentsOf: ranked)
                }
            }

            // A RAW file goes in RAW/ when the shot also has a JPEG/HEIC; otherwise beside the others.
            let hasDisplayable = toCopy.contains { $0.mediaKind != .raw }
            func destFolder(_ f: PhotoFile) -> String {
                f.mediaKind == .raw && hasDisplayable ? "\(folder)/\(options.rawFolderName)" : folder
            }

            // One stem for the whole shot so pairs stay matched; bump it until every file fits.
            let stem = (shot.primary.fileName as NSString).deletingPathExtension
            var suffix = 1
            func names(_ n: Int) -> [(PhotoFile, String, String)] {
                var seenInShot: [String: Int] = [:]
                return toCopy.map { f in
                    let ext = (f.fileName as NSString).pathExtension
                    let base = n == 1 ? stem : "\(stem)-\(n)"
                    var name = ext.isEmpty ? base : "\(base).\(ext)"
                    let dir = destFolder(f)
                    // Kept near-duplicates of the same kind share a stem; number them.
                    let key = "\(dir)/\(name.lowercased())"
                    if let count = seenInShot[key] {
                        seenInShot[key] = count + 1
                        name = ext.isEmpty ? "\(base)_v\(count + 1)" : "\(base)_v\(count + 1).\(ext)"
                    } else {
                        seenInShot[key] = 1
                    }
                    return (f, dir, name)
                }
            }
            var candidate = names(suffix)
            while candidate.contains(where: { usedNames[$0.1, default: []].contains($0.2.lowercased()) }) {
                suffix += 1
                candidate = names(suffix)
            }
            for (file, dir, name) in candidate {
                usedNames[dir, default: []].insert(name.lowercased())
                entries.append(PlanEntry(photo: file, action: .copy, destination: "\(dir)/\(name)", reason: category))
                summary.copyFiles += 1
                summary.copyBytes += file.fileSize
                if category == "unsorted" { summary.unsortedFiles += 1 }
                if category == "undated" { summary.undatedFiles += 1 }
            }
            for dup in shot.duplicates {
                let keeper = shot.keepers.first { $0.fileHash == dup.fileHash }
                entries.append(PlanEntry(photo: dup, action: .skip, destination: nil,
                                         reason: "duplicate of \(keeper?.relativePath ?? "another copy")"))
                summary.skippedDuplicates += 1
                summary.skippedBytes += dup.fileSize
            }
        }
        summary.folders = usedNames.count
        return (entries, summary)
    }
}
