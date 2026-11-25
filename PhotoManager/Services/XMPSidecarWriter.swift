import Foundation

/// Writes XMP sidecars (IMG_1234.xmp) next to copied files so other apps see the labels: the event
/// path as a hierarchical keyword ("Asia Trip|Hong Kong|Temples"), people, keywords, rating,
/// description and place. Photo files themselves are never modified.
enum XMPSidecarWriter {
    static let creatorTool = "PhotoManager"

    struct Labels: Equatable {
        var eventPath: [String] = []
        var people: [String] = []
        var keywords: [String] = []
        var rating = 0
        var description: String?
        var city: String?
        var country: String?
        var dateCreated: Date?

        var isEmpty: Bool { eventPath.isEmpty && people.isEmpty && keywords.isEmpty && rating == 0 && (description ?? "").isEmpty }

        mutating func merge(_ other: Labels) {
            if eventPath.isEmpty { eventPath = other.eventPath }
            people = Array(Set(people + other.people)).sorted()
            keywords = Array(Set(keywords + other.keywords)).sorted()
            rating = max(rating, other.rating)
            description = description ?? other.description
            city = city ?? other.city
            country = country ?? other.country
            dateCreated = dateCreated ?? other.dateCreated
        }
    }

    struct Result {
        var written = 0
        var skippedForeign = 0
        var failed = 0
    }

    static func xml(_ labels: Labels) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func bag(_ tag: String, _ items: [String]) -> String {
            guard !items.isEmpty else { return "" }
            return "   <\(tag)><rdf:Bag>\n" + items.map { "    <rdf:li>\(esc($0))</rdf:li>\n" }.joined() + "   </rdf:Bag></\(tag)>\n"
        }
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var attributes = ["xmp:CreatorTool=\"\(creatorTool)\""]
        if labels.rating > 0 { attributes.append("xmp:Rating=\"\(labels.rating)\"") }
        if let d = labels.dateCreated { attributes.append("photoshop:DateCreated=\"\(iso.string(from: d))\"") }
        if let c = labels.city { attributes.append("photoshop:City=\"\(esc(c))\"") }
        if let c = labels.country { attributes.append("photoshop:Country=\"\(esc(c))\"") }

        var hierarchical: [String] = []
        if !labels.eventPath.isEmpty {
            // Every level, so apps that only show leaves still offer "Asia Trip" as a keyword.
            for i in 1...labels.eventPath.count { hierarchical.append(labels.eventPath.prefix(i).joined(separator: "|")) }
        }
        hierarchical += labels.people.map { "People|\($0)" }
        hierarchical += labels.keywords
        let flat = Array(Set(labels.eventPath + labels.people + labels.keywords)).sorted()

        var body = bag("dc:subject", flat) + bag("lr:hierarchicalSubject", hierarchical) + bag("Iptc4xmpExt:PersonInImage", labels.people)
        if let d = labels.description, !d.isEmpty {
            body += "   <dc:description><rdf:Alt><rdf:li xml:lang=\"x-default\">\(esc(d))</rdf:li></rdf:Alt></dc:description>\n"
        }
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="\(creatorTool)">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
            xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
            xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
            \(attributes.joined(separator: "\n    "))>
        \(body)  </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>

        """
    }

    /// Writes sidecars for every verified copy in a plan. Files sharing a folder and name stem (a RAW+JPEG
    /// pair in one folder) share one sidecar; a RAW in RAW/ gets its own.
    static func writeSidecars(planId: Int64, target: URL, db: DatabaseManager) throws -> Result {
        let items: [DatabaseManager.PlanItemRecord] = try db.planItems(planId, status: "verified").filter { item in
            item.action == "copy" && item.photoId != nil
        }
        let ids = items.compactMap(\.photoId)
        let photos = Dictionary(uniqueKeysWithValues: try db.photos(withIds: ids).compactMap { p in p.id.map { ($0, p) } })
        let events = Dictionary(uniqueKeysWithValues: try db.events().map { ($0.id, $0) })

        var tagsByPhoto: [Int64: [(String, TagKind)]] = [:]
        let tagRows = try db.rawRows("""
            SELECT pt.photo_id, t.name, t.kind FROM photo_tags pt JOIN tags t ON t.id = pt.tag_id
            WHERE pt.photo_id IN (SELECT value FROM json_each(?))
            """, [DatabaseManager.jsonArray(ids)])
        for row in tagRows {
            guard let id = row[0] as? Int64, let name = row[1] as? String else { continue }
            tagsByPhoto[id, default: []].append((name, TagKind(rawValue: row[2] as? String ?? "") ?? .keyword))
        }
        let places = GeoService(db: db).cachedPlaces()

        var bySidecar: [String: Labels] = [:]
        for item in items {
            guard let rel = item.destRelativePath, let id = item.photoId, let photo = photos[id] else { continue }
            var labels = Labels()
            if let eventId = photo.eventId {
                let path = db.eventPath(eventId, events: events)
                labels.eventPath = path.map(\.name)
                if let place = path.reversed().compactMap(\.place).first { labels.city = place }
            }
            for (name, kind) in tagsByPhoto[id] ?? [] {
                if kind == .person { labels.people.append(name) } else { labels.keywords.append(name) }
            }
            labels.rating = photo.rating
            labels.description = photo.userDescription
            labels.dateCreated = photo.dateSource == .file ? nil : photo.captureDate
            if let lat = photo.gpsLatitude, let lon = photo.gpsLongitude, let place = places[GeoService.cellKey(latitude: lat, longitude: lon)] {
                labels.city = labels.city ?? place.locality
                labels.country = place.country
            }
            let sidecar = ((rel as NSString).deletingPathExtension) + ".xmp"
            bySidecar[sidecar, default: Labels()].merge(labels)
        }

        var result = Result()
        for (rel, labels) in bySidecar where !labels.isEmpty {
            let url = target.appendingPathComponent(rel)
            if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.contains("x:xmptk=\"\(creatorTool)\"") {
                result.skippedForeign += 1   // someone else's sidecar: leave it alone
                continue
            }
            do {
                try xml(labels).write(to: url, atomically: true, encoding: .utf8)
                result.written += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}
