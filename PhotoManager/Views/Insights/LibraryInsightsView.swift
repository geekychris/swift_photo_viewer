import SwiftUI
import MapKit

// MARK: - Model

/// The filter controls shown in the Insights window, in a form that can be saved.
struct InsightsFilter: Codable, Equatable {
    var text = ""
    var period = ""            // "2019", "2019-03", …
    var eventId: Int64?
    var mediaKind: String?     // MediaKind raw value
    var camera: String?
    var minRating = 0
    var personTagId: Int64?
    var onlyUnfiled = false

    var photoFilter: PhotoFilter {
        var f = PhotoFilter()
        f.text = text.isEmpty ? nil : text
        f.capturePrefix = period.isEmpty ? nil : period
        f.eventId = eventId
        if let kind = mediaKind.flatMap(MediaKind.init(rawValue:)) { f.mediaKinds = [kind] }
        f.cameraModel = camera
        f.minRating = minRating > 0 ? minRating : nil
        if let tag = personTagId { f.tagIds = [tag] }
        f.unassignedOnly = onlyUnfiled
        return f
    }
}

struct SavedInsightView: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rows: PivotDimension
    var columns: PivotDimension?
    var bySize: Bool
    var filter: InsightsFilter
}

@MainActor
final class InsightsModel: ObservableObject {
    let library: PhotoLibrary
    var db: DatabaseManager { library.databaseManager }

    @Published var filter = InsightsFilter()
    @Published var rows: PivotDimension = .year
    @Published var columns: PivotDimension?
    @Published var bySize = false
    @Published var sortByValue = false
    @Published var data: [PivotRow] = []
    @Published var total: (count: Int, bytes: Int64) = (0, 0)
    @Published var isLoading = false

    @Published var events: [Int64: PhotoEvent] = [:]
    @Published var people: [PhotoTag] = []
    @Published var cameras: [String] = []
    @Published var saved: [SavedInsightView] = []

    private var loadTask: Task<Void, Never>?
    private static let savedKey = "InsightsSavedViews"

    init(library: PhotoLibrary) {
        self.library = library
        if let data = UserDefaults.standard.data(forKey: Self.savedKey),
           let views = try? JSONDecoder().decode([SavedInsightView].self, from: data) {
            saved = views
        }
    }

    func reloadLookups() {
        events = Dictionary(uniqueKeysWithValues: ((try? db.events()) ?? []).map { ($0.id, $0) })
        people = (try? db.tags(kind: .person)) ?? []
        cameras = ((try? db.pivot(.camera)) ?? []).map(\.key).filter { !$0.isEmpty }
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        let db = self.db, f = filter.photoFilter, rows = self.rows, columns = self.columns
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                ((try? db.pivot(rows, by: columns, filter: f)) ?? [], (try? db.countPhotos(matching: f)) ?? (0, 0))
            }.value
            guard !Task.isCancelled else { return }
            data = result.0
            total = result.1
            isLoading = false
        }
    }

    /// Human label for a dimension key.
    func label(_ dim: PivotDimension, _ key: String) -> String {
        if key.isEmpty { return "(none)" }
        switch dim {
        case .event, .topEvent:
            guard let id = Int64(key) else { return key }
            return db.eventPath(id, events: events).map(\.name).joined(separator: " ▸ ")
        case .root:
            return Int64(key).flatMap { library.rootDirectory(id: $0)?.name } ?? key
        case .directory:
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            let root = Int64(parts.first ?? "").flatMap { library.rootDirectory(id: $0)?.name } ?? "?"
            return parts.count > 1 && !parts[1].isEmpty ? "\(root)/\(parts[1])" : root
        case .weekday:
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            return Int(key).map { names[$0 % 7] } ?? key
        case .hour:
            return "\(key):00"
        case .rating:
            return key == "0" ? "Unrated" : String(repeating: "★", count: Int(key) ?? 0)
        default:
            return key
        }
    }

    /// Filter for the photos behind one bar or cell.
    func drillFilter(_ key: String, _ key2: String? = nil) -> PhotoFilter {
        var f = filter.photoFilter
        f.dimensionKeys.append(DimensionKey(dimension: rows, key: key))
        if let columns, let key2 { f.dimensionKeys.append(DimensionKey(dimension: columns, key: key2)) }
        return f
    }

    func save(name: String) {
        saved.append(SavedInsightView(name: name, rows: rows, columns: columns, bySize: bySize, filter: filter))
        persist()
    }

    func apply(_ view: SavedInsightView) {
        rows = view.rows
        columns = view.columns
        bySize = view.bySize
        filter = view.filter
        reload()
    }

    func delete(_ view: SavedInsightView) {
        saved.removeAll { $0.id == view.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.savedKey) }
    }
}

// MARK: - Window

struct LibraryInsightsView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @StateObject private var holder = Holder()

    var body: some View {
        Group {
            if let model = holder.model { InsightsContent(model: model) } else { ProgressView() }
        }
        .onAppear { if holder.model == nil { holder.model = InsightsModel(library: photoLibrary) } }
    }

    @MainActor final class Holder: ObservableObject { @Published var model: InsightsModel? }
}

private enum InsightsTab: String, CaseIterable, Identifiable {
    case pivot = "Pivot", calendar = "Calendar", map = "Map", saved = "Saved views"
    var id: String { rawValue }
}

private struct InsightsContent: View {
    @ObservedObject var model: InsightsModel
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var tab: InsightsTab = .pivot
    @State private var drill: DrillRequest?

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(model: model)
            Divider()
            Picker("", selection: $tab) {
                ForEach(InsightsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 500)
            .padding(8)
            switch tab {
            case .pivot: PivotTab(model: model, drill: $drill)
            case .calendar: CalendarTab(model: model, drill: $drill)
            case .map: MapTab(model: model, drill: $drill)
            case .saved: SavedTab(model: model) { tab = .pivot }
            }
        }
        .onAppear {
            model.reloadLookups()
            model.reload()
        }
        .onChange(of: model.filter) { model.reload() }
        .onChange(of: model.rows) { model.reload() }
        .onChange(of: model.columns) { model.reload() }
        .onChange(of: photoLibrary.libraryVersion) {
            model.reloadLookups()
            model.reload()
        }
        .sheet(item: $drill) { request in
            DrillPhotosSheet(title: request.title, filter: request.filter)
        }
    }
}

struct DrillRequest: Identifiable {
    let id = UUID()
    let title: String
    let filter: PhotoFilter
}

private struct FilterBar: View {
    @ObservedObject var model: InsightsModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            TextField("Search names, folders, tags, events…", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)
                .onSubmit { model.filter.text = text }
                .onChange(of: text) {
                    let value = text
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if value == text { model.filter.text = value }
                    }
                }
            TextField("Period (2019 or 2019-03)", text: $model.filter.period)
                .textFieldStyle(.roundedBorder).frame(width: 160)
            Picker("Event", selection: $model.filter.eventId) {
                Text("Any event").tag(Int64?.none)
                ForEach(model.events.values.sorted { model.label(.event, String($0.id)) < model.label(.event, String($1.id)) }) { e in
                    Text(model.label(.event, String(e.id))).tag(Optional(e.id))
                }
            }
            .frame(width: 200)
            Picker("Person", selection: $model.filter.personTagId) {
                Text("Anyone").tag(Int64?.none)
                ForEach(model.people) { Text($0.name).tag(Optional($0.id)) }
            }
            .frame(width: 150)
            Picker("Camera", selection: $model.filter.camera) {
                Text("Any camera").tag(String?.none)
                ForEach(model.cameras, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .frame(width: 180)
            Picker("Kind", selection: $model.filter.mediaKind) {
                Text("All kinds").tag(String?.none)
                ForEach(MediaKind.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag(Optional($0.rawValue)) }
            }
            .frame(width: 120)
            Stepper("★ ≥ \(model.filter.minRating)", value: $model.filter.minRating, in: 0...5)
            Toggle("Unfiled only", isOn: $model.filter.onlyUnfiled)
            Spacer()
            Text("\(model.total.count) photos · \(ByteCountFormatter.string(fromByteCount: model.total.bytes, countStyle: .file))")
                .font(.caption).foregroundColor(.secondary).monospacedDigit()
        }
        .labelsHidden()
        .padding(10)
    }
}

// MARK: - Pivot

private struct PivotTab: View {
    @ObservedObject var model: InsightsModel
    @Binding var drill: DrillRequest?
    @State private var savingName = ""
    @State private var showingSave = false

    private static let groups: [(String, [PivotDimension])] = [
        ("Time", [.year, .month, .week, .day, .weekday, .hour]),
        ("Organisation", [.topEvent, .event, .person, .keyword, .rating, .colorTag]),
        ("Place", [.country, .city]),
        ("Camera", [.camera, .lens, .focalLength, .aperture, .iso]),
        ("Files", [.mediaKind, .fileExtension, .dateSource, .root, .directory]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rows")
                dimensionPicker($model.rows)
                Text("Columns")
                Picker("", selection: $model.columns) {
                    Text("None").tag(PivotDimension?.none)
                    ForEach(Self.groups, id: \.0) { group in
                        Section(group.0) {
                            ForEach(group.1) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                }
                .frame(width: 170)
                Picker("", selection: $model.bySize) {
                    Text("Count").tag(false)
                    Text("Size").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 130)
                if model.columns == nil {
                    Toggle("Sort by value", isOn: $model.sortByValue)
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button("Save view…") { showingSave = true }
            }
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            Divider()
            if model.columns == nil {
                BarList(model: model, drill: $drill)
            } else {
                HeatMatrix(model: model, drill: $drill)
            }
        }
        .alert("Save view", isPresented: $showingSave) {
            TextField("Name", text: $savingName)
            Button("Save") { model.save(name: savingName.isEmpty ? "\(model.rows.title) view" : savingName); savingName = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func dimensionPicker(_ binding: Binding<PivotDimension>) -> some View {
        Picker("", selection: binding) {
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { Text($0.title).tag($0) }
                }
            }
        }
        .frame(width: 170)
    }
}

private struct BarList: View {
    @ObservedObject var model: InsightsModel
    @Binding var drill: DrillRequest?

    var body: some View {
        let rows = model.sortByValue
            ? model.data.sorted { value($0) > value($1) }
            : model.data
        let maxValue = max(1, rows.map(value).max() ?? 1)
        List(rows) { row in
            Button {
                drill = DrillRequest(title: "\(model.rows.title): \(model.label(model.rows, row.key))", filter: model.drillFilter(row.key))
            } label: {
                HStack {
                    Text(model.label(model.rows, row.key)).frame(width: 260, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.75))
                            .frame(width: max(2, geo.size.width * CGFloat(value(row)) / CGFloat(maxValue)))
                    }
                    .frame(height: 14)
                    Text(model.bySize ? ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file) : "\(row.count)")
                        .monospacedDigit().foregroundColor(.secondary).frame(width: 90, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func value(_ row: PivotRow) -> Int64 { model.bySize ? row.bytes : Int64(row.count) }
}

private struct HeatMatrix: View {
    @ObservedObject var model: InsightsModel
    @Binding var drill: DrillRequest?
    private let maxColumns = 14

    var body: some View {
        let columnTotals = Dictionary(grouping: model.data, by: { $0.key2 ?? "" }).mapValues { $0.reduce(0) { $0 + value($1) } }
        let columns = columnTotals.sorted { $0.value > $1.value }.prefix(maxColumns).map(\.key).sorted()
        let rowKeys = Array(Set(model.data.map(\.key))).sorted()
        let cells = Dictionary(uniqueKeysWithValues: model.data.map { ("\($0.key)|\($0.key2 ?? "")", $0) })
        let maxValue = max(1, model.data.map(value).max() ?? 1)
        let colDim = model.columns ?? .camera

        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("")
                    ForEach(columns, id: \.self) { c in
                        Text(model.label(colDim, c)).font(.caption).lineLimit(2).frame(width: 90)
                    }
                }
                ForEach(rowKeys, id: \.self) { r in
                    GridRow {
                        Text(model.label(model.rows, r)).font(.caption).lineLimit(1).frame(width: 200, alignment: .leading)
                        ForEach(columns, id: \.self) { c in
                            let cell = cells["\(r)|\(c)"]
                            let v = cell.map(value) ?? 0
                            Button {
                                drill = DrillRequest(title: "\(model.label(model.rows, r)) × \(model.label(colDim, c))", filter: model.drillFilter(r, c))
                            } label: {
                                Text(v == 0 ? "" : (model.bySize ? ByteCountFormatter.string(fromByteCount: v, countStyle: .file) : "\(v)"))
                                    .font(.caption2).monospacedDigit()
                                    .frame(width: 90, height: 24)
                                    .background(Color.accentColor.opacity(v == 0 ? 0.03 : 0.12 + 0.8 * Double(v) / Double(maxValue)))
                                    .foregroundColor(Double(v) / Double(maxValue) > 0.55 ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(v == 0)
                        }
                    }
                }
            }
            .padding()
            if columnTotals.count > maxColumns {
                Text("Showing the \(maxColumns) largest of \(columnTotals.count) columns.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
            }
        }
    }

    private func value(_ row: PivotRow) -> Int64 { model.bySize ? row.bytes : Int64(row.count) }
}

// MARK: - Calendar heatmap

private struct CalendarTab: View {
    @ObservedObject var model: InsightsModel
    @Binding var drill: DrillRequest?
    @State private var days: [String: Int] = [:]
    @State private var years: [String] = []
    @State private var year = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 140)
                Text("\(days.filter { $0.key.hasPrefix(year) }.count) shooting days, \(days.filter { $0.key.hasPrefix(year) }.values.reduce(0, +)) photos")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            if let start = yearStart {
                ScrollView(.horizontal) {
                    CalendarGrid(start: start, days: days, onTap: { key in
                        var f = model.filter.photoFilter
                        f.capturePrefix = key
                        drill = DrillRequest(title: key, filter: f)
                    })
                    .padding()
                }
            }
            Spacer()
        }
        .task(id: model.filter) { await load() }
    }

    private var yearStart: Date? {
        guard let y = Int(year) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: 1, day: 1))
    }

    private func load() async {
        let db = model.db
        var f = model.filter.photoFilter
        f.capturePrefix = nil
        let rows = await Task.detached { (try? db.pivot(.day, filter: f)) ?? [] }.value
        days = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.count) })
        years = Array(Set(rows.map { String($0.key.prefix(4)) })).filter { !$0.isEmpty }.sorted(by: >)
        if !years.contains(year) { year = years.first ?? "" }
    }
}

private struct CalendarGrid: View {
    let start: Date
    let days: [String: Int]
    let onTap: (String) -> Void
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let cal = Calendar.current
        let offset = (cal.component(.weekday, from: start) + 5) % 7  // Monday first
        let year = cal.component(.year, from: start)
        let count = cal.range(of: .day, in: .year, for: start)?.count ?? 365
        let maxCount = max(1, days.filter { $0.key.hasPrefix(String(year)) }.values.max() ?? 1)
        let weeks = (count + offset + 6) / 7
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption2).frame(width: 14, height: 14)
                }
            }
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let index = week * 7 + weekday - offset
                        if index >= 0 && index < count, let date = cal.date(byAdding: .day, value: index, to: start) {
                            let key = Self.keyFormatter.string(from: date)
                            let n = days[key] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(n == 0 ? Color.secondary.opacity(0.12) : Color.green.opacity(0.25 + 0.75 * sqrt(Double(n) / Double(maxCount))))
                                .frame(width: 14, height: 14)
                                .help("\(key): \(n) photos")
                                .onTapGesture { if n > 0 { onTap(key) } }
                        } else {
                            Color.clear.frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Map

private struct MapTab: View {
    @ObservedObject var model: InsightsModel
    @Binding var drill: DrillRequest?
    @State private var points: [MapPoint] = []
    @State private var detailed = false
    @State private var position: MapCameraPosition = .automatic

    struct MapPoint: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let count: Int
        let box: GeoBox
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Fine grid (≈10 km)", isOn: $detailed)
                Text("\(points.reduce(0) { $0 + $1.count }) photos with GPS in \(points.count) areas")
                    .foregroundColor(.secondary)
                Spacer()
                Text("Photos from cameras without GPS appear once you file them under an event with a place.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            Map(position: $position) {
                ForEach(points) { point in
                    Annotation("", coordinate: point.coordinate) {
                        Button {
                            var f = model.filter.photoFilter
                            f.geoBox = point.box
                            drill = DrillRequest(title: "\(point.count) photos near \(String(format: "%.2f, %.2f", point.coordinate.latitude, point.coordinate.longitude))", filter: f)
                        } label: {
                            Text("\(point.count)")
                                .font(.caption2).bold()
                                .padding(6)
                                .frame(minWidth: 26, minHeight: 26)
                                .background(Circle().fill(Color.accentColor.opacity(0.85)))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: "\(model.filter.hashValueString)-\(detailed)") { await load() }
    }

    private func load() async {
        let db = model.db, f = model.filter.photoFilter, cell = detailed ? 0.1 : 1.0
        let rows = await Task.detached { (try? db.gpsClusters(filter: f, cellDegrees: cell)) ?? [] }.value
        points = rows.map { MapPoint(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), count: $0.count, box: $0.box) }
    }
}

private extension InsightsFilter {
    var hashValueString: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

// MARK: - Saved views

private struct SavedTab: View {
    @ObservedObject var model: InsightsModel
    let onOpen: () -> Void

    var body: some View {
        if model.saved.isEmpty {
            ContentUnavailableView("No saved views", systemImage: "bookmark",
                                   description: Text("Set up a pivot and filters, then press “Save view…”."))
        } else {
            List(model.saved) { view in
                HStack {
                    VStack(alignment: .leading) {
                        Text(view.name).font(.headline)
                        Text(describe(view)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open") { model.apply(view); onOpen() }
                    Button(role: .destructive) { model.delete(view) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func describe(_ v: SavedInsightView) -> String {
        var parts = ["\(v.rows.title)" + (v.columns.map { " × \($0.title)" } ?? "")]
        if !v.filter.text.isEmpty { parts.append("“\(v.filter.text)”") }
        if !v.filter.period.isEmpty { parts.append(v.filter.period) }
        if let e = v.filter.eventId { parts.append(model.label(.event, String(e))) }
        if v.filter.minRating > 0 { parts.append("★≥\(v.filter.minRating)") }
        if let k = v.filter.mediaKind { parts.append(k) }
        if let c = v.filter.camera { parts.append(c) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Drill-down grid

struct DrillPhotosSheet: View {
    let title: String
    let filter: PhotoFilter
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotoFile] = []
    @State private var total = 0
    @State private var selected: PhotoFile?
    @State private var loadingMore = false
    private let pageSize = 300

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3).bold().lineLimit(1)
                Text("\(total) photos").foregroundColor(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                    ForEach(photos) { photo in
                        AsyncThumbnail(photo: photo, size: 130)
                            .cornerRadius(4)
                            .onTapGesture { selected = photo }
                            .onAppear { if photo == photos.last { Task { await loadMore() } } }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, idealWidth: 1100, minHeight: 500, idealHeight: 750)
        .task { await loadMore() }
        .sheet(item: $selected) { PhotoDetailView(photo: $0) }
    }

    private func loadMore() async {
        guard !loadingMore, photos.count < max(total, 1) || photos.isEmpty else { return }
        loadingMore = true
        let db = photoLibrary.databaseManager, f = filter, offset = photos.count, size = pageSize
        let (page, count) = await Task.detached {
            ((try? db.photos(matching: f, sort: .captureAscending, limit: size, offset: offset)) ?? [],
             (try? db.countPhotos(matching: f).count) ?? 0)
        }.value
        photos += page
        total = count
        loadingMore = false
    }
}
