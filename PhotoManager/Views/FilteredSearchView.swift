import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "filter")

struct FilteredSearchView: View {
    let searchText: String
    let startDate: Date?
    let endDate: Date?
    let camera: String
    let minAperture: Double?
    let maxAperture: Double?
    let minISO: Int?
    let maxISO: Int?
    let minRating: Int
    let selectedColors: Set<String>
    let filterDirectoryId: Int64?
    let filterSubdirectoryPath: String?
    let filterTimelinePeriod: String?
    @Binding var selectedPhoto: PhotoFile?
    
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @StateObject private var actions = PhotoActionCenter()
    @State private var filteredPhotos: [PhotoFile] = []
    /// Matching photos in total; nil when only a lower bound is known (in-memory filters hit the limit).
    @State private var totalCount: Int?
    @State private var isSearching = false
    @State private var thumbnailSize: CGFloat = 200

    private static let resultLimit = 5000
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    private var searchContext: String? {
        if let directoryId = filterDirectoryId {
            if let directory = photoLibrary.rootDirectories.first(where: { $0.id == directoryId }) {
                if let subdir = filterSubdirectoryPath {
                    return "📁 \(directory.name) › \(subdir.isEmpty ? "Files in top folder" : subdir)"
                } else {
                    return "📁 \(directory.name)"
                }
            }
            return "📁 Directory"
        } else if let period = filterTimelinePeriod {
            // Format the period nicely
            let formatter = DateFormatter()
            if period.contains("W") {
                let parts = period.split(separator: "-")
                if parts.count == 2, let weekNum = parts[1].dropFirst().description as String? {
                    return "📅 Week \(weekNum), \(parts[0])"
                }
            } else if period.count == 10 {
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: period) {
                    formatter.dateFormat = "MMM d, yyyy"
                    return "📅 \(formatter.string(from: date))"
                }
            } else {
                formatter.dateFormat = "yyyy-MM"
                if let date = formatter.date(from: period) {
                    formatter.dateFormat = "MMMM yyyy"
                    return "📅 \(formatter.string(from: date))"
                }
            }
            return "📅 Timeline"
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with result count and context
            VStack(spacing: 4) {
                HStack {
                    Text("Search Results")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if isSearching {
                        ProgressView().controlSize(.small)
                    }
                    Text(resultCountText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let context = searchContext {
                    HStack {
                        Text("Searching in: \(context)")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Thumbnail size control
            HStack {
                Text("Thumbnail Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $thumbnailSize, in: 100...400, step: 50)
                    .frame(width: 200)
                
                Text("\(Int(thumbnailSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Results grid
            if filteredPhotos.isEmpty && !isSearching {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    
                    Text("No photos found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Try adjusting your search criteria")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredPhotos) { photo in
                            PhotoThumbnailView(
                                photo: photo,
                                thumbnailSize: thumbnailSize,
                                onTap: {
                                    selectedPhoto = photo
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .photoActions(actions)
        .task(id: query) {
            // Debounce typing; a newer query cancels this task.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performFilteredSearch(query)
        }
        .onChange(of: photoLibrary.libraryVersion) {
            Task { await performFilteredSearch(query) }
        }
    }

    private var resultCountText: String {
        let shown = filteredPhotos.count
        guard let total = totalCount else { return "Showing first \(shown) matches" }
        if total > shown { return "Showing \(shown) of \(total) photos" }
        return "\(total) photos found"
    }

    // MARK: - Query

    /// Everything that affects the results, so one change triggers one (debounced) search.
    private struct SearchQuery: Equatable {
        var filter: PhotoFilter
        var camera: String
        var minAperture: Double?
        var maxAperture: Double?
        var minISO: Int?
        var maxISO: Int?
    }

    private var query: SearchQuery {
        var filter = PhotoFilter()
        if let directoryId = filterDirectoryId {
            filter.rootDirectoryId = directoryId
            if let subdir = filterSubdirectoryPath {
                filter.directoryPath = subdir
                // "" is the files directly in the root; other folders include their subfolders.
                filter.includeSubdirectories = !subdir.isEmpty
            }
        } else if let period = filterTimelinePeriod {
            let periodFilter = PhotoFilter.forPeriod(period)
            filter.captureFrom = periodFilter.captureFrom
            filter.captureTo = periodFilter.captureTo
            filter.capturePrefix = periodFilter.capturePrefix
        }
        let text = searchText.trimmingCharacters(in: .whitespaces)
        filter.text = text.isEmpty ? nil : text
        filter.minRating = minRating > 0 ? minRating : nil
        filter.colorTags = selectedColors

        let calendar = Calendar.current
        if let start = startDate {
            let from = calendar.startOfDay(for: start)
            filter.captureFrom = max(filter.captureFrom ?? from, from)
        }
        if let end = endDate, let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) {
            filter.captureTo = min(filter.captureTo ?? to, to)
        }
        return SearchQuery(filter: filter, camera: camera.trimmingCharacters(in: .whitespaces),
                           minAperture: minAperture, maxAperture: maxAperture, minISO: minISO, maxISO: maxISO)
    }

    private func performFilteredSearch(_ query: SearchQuery) async {
        isSearching = true
        let db = photoLibrary.databaseManager
        let limit = Self.resultLimit
        let (photos, total) = await Task.detached(priority: .userInitiated) { () -> ([PhotoFile], Int?) in
            do {
                return try Self.run(query, db: db, limit: limit)
            } catch {
                logger.error("Search failed: \(error.localizedDescription, privacy: .public)")
                return ([], 0)
            }
        }.value
        guard query == self.query else { return } // a newer search is under way
        filteredPhotos = photos
        totalCount = total
        isSearching = false
    }

    /// Runs the search in SQL. Camera substring, aperture and ISO ranges are applied in memory,
    /// scanning pages until `limit` matches are found.
    private static func run(_ query: SearchQuery, db: DatabaseManager, limit: Int) throws -> ([PhotoFile], Int?) {
        var filter = query.filter
        var cameraNeedle: String?
        if !query.camera.isEmpty {
            // Narrow to the camera models containing the text; one model can be matched in SQL.
            let models = try db.pivot(.camera, filter: filter)
                .map(\.key)
                .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(query.camera) }
            if models.isEmpty { return ([], 0) }
            if models.count == 1 { filter.cameraModel = models[0] } else { cameraNeedle = query.camera }
        }

        let inMemory: ((PhotoFile) -> Bool)?
        if cameraNeedle != nil || query.minAperture != nil || query.maxAperture != nil || query.minISO != nil || query.maxISO != nil {
            inMemory = { photo in
                if let needle = cameraNeedle {
                    guard let model = photo.exifCameraModel, model.localizedCaseInsensitiveContains(needle) else { return false }
                }
                if query.minAperture != nil || query.maxAperture != nil {
                    guard let aperture = photo.exifAperture else { return false }
                    if let minAp = query.minAperture, aperture < minAp { return false }
                    if let maxAp = query.maxAperture, aperture > maxAp { return false }
                }
                if query.minISO != nil || query.maxISO != nil {
                    guard let iso = photo.exifIso else { return false }
                    if let minIso = query.minISO, iso < minIso { return false }
                    if let maxIso = query.maxISO, iso > maxIso { return false }
                }
                return true
            }
        } else {
            inMemory = nil
        }

        guard let predicate = inMemory else {
            let total = try db.countPhotos(matching: filter).count
            let photos = try db.photos(matching: filter, sort: .captureDescending, limit: limit)
            return (photos, total)
        }

        var matches: [PhotoFile] = []
        var offset = 0
        let batch = 2000
        while true {
            let page = try db.photos(matching: filter, sort: .captureDescending, limit: batch, offset: offset)
            for photo in page where predicate(photo) {
                matches.append(photo)
                if matches.count >= limit { return (matches, nil) }
            }
            if page.count < batch { return (matches, matches.count) }
            offset += batch
        }
    }
}
