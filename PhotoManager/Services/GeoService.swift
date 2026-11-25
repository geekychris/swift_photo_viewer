import Foundation
import CoreLocation
import os.log

/// Turns photo GPS positions into place names using Apple's geocoder (online). Positions are grouped
/// into 0.1° cells (about 11 km), so a trip needs only a few dozen lookups; results are cached in
/// geo_cells and never repeated.
final class GeoService {
    private static let logger = Logger(subsystem: "com.photomarger", category: "geo")
    private let db: DatabaseManager

    struct Place: Hashable {
        let country: String?
        let locality: String?
        let area: String?
        var label: String? { locality ?? area ?? country }
    }

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    static func cellKey(latitude: Double, longitude: Double) -> String {
        // Must match the SQL expression CAST(lat * 10 AS INTEGER) || ',' || CAST(lon * 10 AS INTEGER):
        // integer truncation of the same IEEE product is identical in both, unlike decimal rounding.
        "\(Int(latitude * 10)),\(Int(longitude * 10))"
    }
    
    /// Cached places for every looked-up cell.
    func cachedPlaces() -> [String: Place] {
        var map: [String: Place] = [:]
        let rows = (try? db.executeRawSQLSync("SELECT cell, country, locality, area FROM geo_cells")) ?? []
        for row in rows {
            guard let cell = row[0] else { continue }
            map[cell] = Place(country: row[1], locality: row[2], area: row[3])
        }
        return map
    }

    /// Looks up pending cells one at a time (Apple throttles bursts). Returns the number resolved.
    func lookUpPending(limit: Int = 200, progress: @escaping (Int, Int) -> Void) async -> Int {
        guard let pending = try? db.pendingGeoCells(limit: limit), !pending.isEmpty else { return 0 }
        let geocoder = CLGeocoder()
        var resolved = 0
        for (index, cell) in pending.enumerated() {
            if Task.isCancelled { break }
            progress(index, pending.count)
            do {
                let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: cell.lat, longitude: cell.lon))
                let mark = marks.first
                try db.saveGeoCell(cell.cell, country: mark?.country, locality: mark?.locality,
                                   area: mark?.administrativeArea ?? mark?.name)
                resolved += 1
            } catch let error as CLError where error.code == .network {
                Self.logger.warning("Geocoding throttled or offline; stopping for now")
                break
            } catch {
                // Open sea and similar: remember the miss so it isn't retried every time.
                try? db.saveGeoCell(cell.cell, country: nil, locality: nil, area: nil)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        progress(pending.count, pending.count)
        return resolved
    }
}

extension DatabaseManager {
    /// Small synchronous helper for read-only lookups returning text columns.
    func executeRawSQLSync(_ sql: String) throws -> [[String?]] {
        var rows: [[String?]] = []
        for row in try rawRows(sql) { rows.append(row.map { $0 as? String }) }
        return rows
    }
}
