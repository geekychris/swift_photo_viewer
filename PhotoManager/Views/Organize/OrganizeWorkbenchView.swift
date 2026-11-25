import SwiftUI
import AppKit

// MARK: - Session state

/// State for one organise session: the analysed shots and clusters, the event tree, and the plan.
/// Event assignments are written to the database immediately, so closing the window loses nothing.
@MainActor
final class OrganizeSession: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case analyse, label, review, plan, copy
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .analyse: return "1 Analyse"
            case .label: return "2 Group & label"
            case .review: return "3 Near-copies"
            case .plan: return "4 Plan"
            case .copy: return "5 Copy"
            }
        }
    }

    let library: PhotoLibrary
    var db: DatabaseManager { library.databaseManager }

    @Published var step: Step = .analyse
    @Published var selectedRootIds: Set<Int64> = []
    @Published var settings = ClusterSettings()
    @Published var isWorking = false
    @Published var status = ""
    @Published var progress: Double = 0

    @Published var shots: [Shot] = []
    @Published var stats = DuplicateStats()
    @Published var clusters: [ShotCluster] = []
    @Published var events: [PhotoEvent] = []
    @Published var places: [String: GeoService.Place] = [:]
    @Published var pendingGeoCells = 0

    @Published var selectedEventId: Int64?
    @Published var selectedClusterIds: Set<String> = []
    @Published var showAssigned = true

    @Published var layout = OrganizeEngine.LayoutOptions()
    @Published var targetURL: URL?
    @Published var planEntries: [OrganizeEngine.PlanEntry] = []
    @Published var planSummary = OrganizeEngine.PlanSummary()
    @Published var planId: Int64?
    @Published var outcome: PlanExecutor.Outcome?
    @Published var executorProgress = PlanExecutor.Progress()
    @Published var writeSidecars = true
    @Published var sidecarSummary: String?

    private var workTask: Task<Void, Never>?

    init(library: PhotoLibrary) {
        self.library = library
        selectedRootIds = Set(library.rootDirectories.compactMap(\.id))
        reloadEvents()
    }

    var eventMap: [Int64: PhotoEvent] { Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) }) }

    func eventPathName(_ id: Int64?) -> String? {
        guard let id else { return nil }
        let names = db.eventPath(id, events: eventMap).map(\.name)
        return names.isEmpty ? nil : names.joined(separator: " ▸ ")
    }

    func reloadEvents() {
        events = (try? db.events()) ?? []
    }

    // MARK: Analyse

    func analyse() {
        workTask?.cancel()
        isWorking = true
        status = "Loading catalogue…"
        let db = self.db
        let roots = selectedRootIds
        let settings = self.settings
        let allRoots = Set(library.rootDirectories.compactMap(\.id))
        workTask = Task {
            let geo = GeoService(db: db)
            let result = await Task.detached(priority: .userInitiated) { () -> ([Shot], DuplicateStats, [ShotCluster], [String: GeoService.Place], Int) in
                var photos: [PhotoFile] = []
                var filter = PhotoFilter()
                if roots == allRoots {
                    photos = (try? db.photos(matching: filter, sort: .captureAscending)) ?? []
                } else {
                    for root in roots {
                        filter.rootDirectoryId = root
                        photos += (try? db.photos(matching: filter, sort: .captureAscending)) ?? []
                    }
                }
                let (shots, stats) = OrganizeEngine.buildShots(photos)
                let places = geo.cachedPlaces()
                let clusters = OrganizeEngine.cluster(shots, settings: settings, placeName: Self.placeNamer(places))
                let pending = (try? db.pendingGeoCells(limit: 10_000).count) ?? 0
                return (shots, stats, clusters, places, pending)
            }.value
            guard !Task.isCancelled else { return }
            (shots, stats, clusters, places, pendingGeoCells) = result
            isWorking = false
            status = "\(stats.files) files → \(stats.shots) shots in \(clusters.count) groups"
        }
    }

    nonisolated static func placeNamer(_ places: [String: GeoService.Place]) -> (Shot) -> String? {
        { shot in
            guard let lat = shot.latitude, let lon = shot.longitude else { return nil }
            return places[GeoService.cellKey(latitude: lat, longitude: lon)]?.label
        }
    }

    func recluster() {
        clusters = OrganizeEngine.cluster(shots, settings: settings, placeName: Self.placeNamer(places))
    }

    func lookUpPlaces() {
        workTask?.cancel()
        isWorking = true
        let geo = GeoService(db: db)
        workTask = Task {
            let resolved = await geo.lookUpPending(limit: 300) { done, total in
                Task { @MainActor in
                    self.progress = total > 0 ? Double(done) / Double(total) : 0
                    self.status = "Looking up places \(done)/\(total)…"
                }
            }
            places = geo.cachedPlaces()
            pendingGeoCells = (try? db.pendingGeoCells(limit: 10_000).count) ?? 0
            recluster()
            isWorking = false
            status = "Found \(resolved) places"
        }
    }

    func cancelWork() {
        workTask?.cancel()
        isWorking = false
        status = "Cancelled"
    }

    // MARK: Events and assignment

    @discardableResult
    func createEvent(name: String, parentId: Int64?, kind: String, place: String?) -> Int64? {
        do {
            let id = try db.createEvent(name: name, parentId: parentId, kind: kind, place: place)
            reloadEvents()
            selectedEventId = id
            return id
        } catch {
            status = "Could not create event: \(error.localizedDescription)"
            return nil
        }
    }

    func assign(shots selected: [Shot], to eventId: Int64?) {
        let ids = selected.flatMap { $0.allFiles.compactMap(\.id) }
        do {
            try db.assignPhotos(ids, toEvent: eventId)
        } catch {
            status = "Could not assign: \(error.localizedDescription)"
            return
        }
        let idSet = Set(ids)
        // Update in memory rather than reloading the whole catalogue.
        shots = shots.map { shot in
            guard shot.allFiles.contains(where: { $0.id.map(idSet.contains) ?? false }) else { return shot }
            var s = shot
            s.keepers = s.keepers.map { var f = $0; if f.id.map(idSet.contains) ?? false { f.eventId = eventId }; return f }
            s.duplicates = s.duplicates.map { var f = $0; if f.id.map(idSet.contains) ?? false { f.eventId = eventId }; return f }
            return s
        }
        recluster()
        reloadEvents()
        library.libraryDidChange(refreshDuplicates: false)
        status = "Assigned \(selected.count) shots to \(eventPathName(eventId) ?? "no event")"
    }

    func assign(clusters ids: Set<String>, to eventId: Int64?) {
        let selected = allClusters.filter { ids.contains($0.id) }.flatMap(\.shots)
        assign(shots: Array(Set(selected)), to: eventId)
    }

    /// Clusters and their child sessions, flattened.
    var allClusters: [ShotCluster] { clusters.flatMap { [$0] + $0.children } }

    func renameEvent(_ event: PhotoEvent, name: String, kind: String, place: String?) {
        try? db.updateEvent(event.id, name: name, kind: kind, place: place, notes: event.notes)
        reloadEvents()
    }

    func deleteEvent(_ event: PhotoEvent) {
        try? db.deleteEvent(event.id)
        // Clear the assignment in memory for this event and its descendants.
        var doomed: Set<Int64> = [event.id]
        var changed = true
        while changed {
            changed = false
            for e in events where e.parentId.map(doomed.contains) ?? false && !doomed.contains(e.id) {
                doomed.insert(e.id)
                changed = true
            }
        }
        shots = shots.map { shot in
            var s = shot
            s.keepers = s.keepers.map { var f = $0; if f.eventId.map(doomed.contains) ?? false { f.eventId = nil }; return f }
            s.duplicates = s.duplicates.map { var f = $0; if f.eventId.map(doomed.contains) ?? false { f.eventId = nil }; return f }
            return s
        }
        if selectedEventId.map(doomed.contains) ?? false { selectedEventId = nil }
        reloadEvents()
        recluster()
        library.libraryDidChange(refreshDuplicates: false)
    }

    func moveEvent(_ event: PhotoEvent, to parent: Int64?) {
        do {
            try db.moveEvent(event.id, toParent: parent)
            reloadEvents()
        } catch {
            status = error.localizedDescription
        }
    }

    func tagPeople(_ names: [String], on selected: [Shot]) {
        let ids = selected.flatMap { $0.allFiles.compactMap(\.id) }
        for name in names {
            if let tag = try? db.tagId(named: name, kind: .person) { try? db.addTag(tag, to: ids) }
        }
        library.libraryDidChange(refreshDuplicates: false)
        status = "Tagged \(selected.count) shots with \(names.joined(separator: ", "))"
    }

    // MARK: Plan and copy

    var nearDuplicateShots: [Shot] { shots.filter(\.hasNearDuplicates) }

    func buildPlan() {
        reloadEvents()
        let (entries, summary) = OrganizeEngine.buildPlan(shots: shots, events: events, options: layout)
        planEntries = entries
        planSummary = summary
        planId = nil
        outcome = nil
    }

    /// Destination folders with file counts, for the preview tree.
    var planFolders: [(folder: String, count: Int)] {
        let folders = planEntries.compactMap { $0.destination.map { ($0 as NSString).deletingLastPathComponent } }
        return Dictionary(grouping: folders, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.folder < $1.folder }
    }

    func saveAndRunPlan() {
        guard let target = targetURL else { return }
        let entries = planEntries
        let roots = library.rootDirectories
        let rootPaths = Dictionary(uniqueKeysWithValues: roots.compactMap { r in r.id.map { ($0, r.path) } })
        let records = entries.map { e in
            DatabaseManager.PlanItemRecord(
                photoId: e.photo.id,
                sourcePath: ((rootPaths[e.photo.rootDirectoryId] ?? "") as NSString).appendingPathComponent(e.photo.relativePath),
                destRelativePath: e.destination, action: e.action.rawValue, reason: e.reason,
                fileHash: e.photo.fileHash, bytes: e.photo.fileSize)
        }
        do {
            planId = try db.savePlan(targetRoot: target.path, summary: planSummary.text, items: records)
        } catch {
            status = "Could not save plan: \(error.localizedDescription)"
            return
        }
        runPlan()
    }

    func runPlan() {
        guard let planId, let target = targetURL else { return }
        step = .copy
        isWorking = true
        outcome = nil
        let db = self.db
        let roots = library.rootDirectories
        workTask = Task {
            do {
                let result = try await PlanExecutor(db: db).execute(planId: planId, target: target, roots: roots) { p in
                    Task { @MainActor in self.executorProgress = p }
                }
                outcome = result
                status = "Copied \(result.verified) files" + (result.failed.isEmpty ? "" : ", \(result.failed.count) failed")
                if writeSidecars {
                    let sidecars = await Task.detached { try? XMPSidecarWriter.writeSidecars(planId: planId, target: target, db: db) }.value
                    if let sidecars {
                        sidecarSummary = "Wrote \(sidecars.written) XMP sidecars" +
                            (sidecars.skippedForeign > 0 ? "; left \(sidecars.skippedForeign) existing sidecars from other apps untouched" : "") +
                            (sidecars.failed > 0 ? "; \(sidecars.failed) failed" : "")
                    }
                }
            } catch {
                status = "Copy stopped: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    func addTargetToLibrary() {
        guard let target = targetURL else { return }
        let bookmark = try? target.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        library.addRootDirectory(path: target.path, name: target.lastPathComponent, bookmarkData: bookmark)
    }

    func trashOriginals(includeNearDuplicates: Bool) -> TrashResult? {
        guard let planId else { return nil }
        let ids = (try? PlanExecutor(db: db).sourcesSafeToTrash(planId: planId, includeNearDuplicates: includeNearDuplicates)) ?? []
        let photos = (try? db.photos(withIds: ids)) ?? []
        // Every one of these now has a verified copy in the target, which may not be catalogued yet,
        // so the last-copy guard would wrongly refuse.
        return library.trashPhotos(photos, allowLastCopy: true)
    }
}

// MARK: - Window

struct OrganizeWorkbenchView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @StateObject private var holder = SessionHolder()

    var body: some View {
        Group {
            if let session = holder.session {
                WorkbenchContent(session: session)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if holder.session == nil { holder.session = OrganizeSession(library: photoLibrary) }
        }
    }

    @MainActor final class SessionHolder: ObservableObject {
        @Published var session: OrganizeSession?
    }
}

private struct WorkbenchContent: View {
    @ObservedObject var session: OrganizeSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Step", selection: $session.step) {
                    ForEach(OrganizeSession.Step.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 700)
                Spacer()
                if session.isWorking {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { session.cancelWork() }
                }
                Text(session.status).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(10)
            Divider()
            switch session.step {
            case .analyse: AnalyseStepView(session: session)
            case .label: LabelStepView(session: session)
            case .review: NearDuplicateStepView(session: session)
            case .plan: PlanStepView(session: session)
            case .copy: CopyStepView(session: session)
            }
        }
    }
}

// MARK: - Step 1: Analyse

private struct AnalyseStepView: View {
    @ObservedObject var session: OrganizeSession
    @EnvironmentObject var photoLibrary: PhotoLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Organise your library").font(.largeTitle).bold()
                Text("Pick the folders to organise. Exact copies collapse into one, RAW+JPEG pairs and Live Photos stay together, and photos are grouped into sessions and trips by time and place so you can name them a group at a time. Nothing on disk changes until the final copy step, which copies into a new folder you choose.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Sources") {
                    VStack(alignment: .leading) {
                        ForEach(photoLibrary.rootDirectories) { root in
                            if let id = root.id {
                                Toggle(isOn: Binding(
                                    get: { session.selectedRootIds.contains(id) },
                                    set: { on in if on { session.selectedRootIds.insert(id) } else { session.selectedRootIds.remove(id) } }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(root.name)
                                        Text(root.path).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        if photoLibrary.rootDirectories.isEmpty {
                            Text("Add a folder in the main window first (the + button), and let it finish scanning.")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Grouping") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledSlider(title: "New session after a gap of", value: Binding(
                            get: { session.settings.sessionGap / 3600 }, set: { session.settings.sessionGap = $0 * 3600 }),
                                      range: 0.5...12, step: 0.5, unit: "hours")
                        LabeledSlider(title: "Sessions closer than this form a trip", value: Binding(
                            get: { session.settings.tripGap / 3600 }, set: { session.settings.tripGap = $0 * 3600 }),
                                      range: 6...96, step: 6, unit: "hours")
                        LabeledSlider(title: "Split when the location jumps by more than", value: $session.settings.splitDistanceKm,
                                      range: 10...1000, step: 10, unit: "km")
                    }
                    .padding(6)
                }

                HStack {
                    Button {
                        session.analyse()
                    } label: {
                        Label(session.shots.isEmpty ? "Analyse" : "Analyse again", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.selectedRootIds.isEmpty || session.isWorking)

                    if !session.shots.isEmpty {
                        Button("Regroup with these settings") { session.recluster() }
                        Button("Next: group & label") { session.step = .label }
                    }
                }

                if !session.shots.isEmpty {
                    StatsGrid(stats: session.stats, clusters: session.clusters)
                    if session.pendingGeoCells > 0 {
                        GroupBox("Places") {
                            HStack {
                                Text("\(session.pendingGeoCells) areas with GPS positions have no place name yet. Looking them up sends those approximate positions (about 11 km precision) to Apple's geocoder.")
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Look up places") { session.lookUpPlaces() }
                                    .disabled(session.isWorking)
                            }
                            .padding(6)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack {
            Text(title).frame(width: 300, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text("\(value, specifier: value < 10 ? "%.1f" : "%.0f") \(unit)").monospacedDigit().frame(width: 90, alignment: .trailing)
        }
    }
}

private struct StatsGrid: View {
    let stats: DuplicateStats
    let clusters: [ShotCluster]
    private static let bytes = ByteCountFormatter()

    var body: some View {
        let trips = clusters.filter { $0.kind == .trip }.count
        let sessions = clusters.filter { $0.kind == .session }.count + clusters.filter { $0.kind == .trip }.reduce(0) { $0 + $1.children.count }
        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 8) {
            GridRow { stat("Files", stats.files); stat("Distinct photos", stats.uniqueContents); stat("Shots", stats.shots) }
            GridRow {
                stat("Exact duplicates", stats.duplicateFiles, detail: Self.bytes.string(fromByteCount: stats.duplicateBytes))
                stat("RAW+JPEG pairs", stats.rawJpegPairs)
                stat("Live Photos", stats.livePhotos)
            }
            GridRow { stat("Near-copies to review", stats.nearDuplicateShots); stat("Undated shots", stats.undatedShots); stat("Trips / sessions", trips, detail: "\(sessions) sessions") }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private func stat(_ title: String, _ value: Int, detail: String? = nil) -> some View {
        VStack(alignment: .leading) {
            Text("\(value)").font(.title2).bold().monospacedDigit()
            Text(title).font(.caption).foregroundColor(.secondary)
            if let detail { Text(detail).font(.caption2).foregroundColor(.secondary) }
        }
    }
}

// MARK: - Step 2: Group & label

private struct LabelStepView: View {
    @ObservedObject var session: OrganizeSession
    @State private var detailCluster: ShotCluster?

    var body: some View {
        HSplitView {
            EventTreePanel(session: session)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            ClusterTimeline(session: session, detailCluster: $detailCluster)
                .frame(minWidth: 600)
        }
        .sheet(item: $detailCluster) { cluster in
            ClusterDetailSheet(session: session, cluster: cluster)
        }
    }
}

struct EventNode: Identifiable {
    let event: PhotoEvent
    var children: [EventNode]?
    var id: Int64 { event.id }

    static func tree(_ events: [PhotoEvent]) -> [EventNode] {
        let byParent = Dictionary(grouping: events, by: \.parentId)
        func build(_ parent: Int64?, depth: Int) -> [EventNode] {
            guard depth < 32 else { return [] }
            return (byParent[parent] ?? []).map { e in
                let kids = build(e.id, depth: depth + 1)
                return EventNode(event: e, children: kids.isEmpty ? nil : kids)
            }
        }
        return build(nil, depth: 0)
    }
}

private struct EventTreePanel: View {
    @ObservedObject var session: OrganizeSession
    @State private var editor: EventEditorState?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Events").font(.headline)
                Spacer()
                Menu {
                    Button("New top-level event…") { editor = EventEditorState(parentId: nil) }
                    if let selected = session.selectedEventId {
                        Button("New sub-event of \(session.eventMap[selected]?.name ?? "selection")…") {
                            editor = EventEditorState(parentId: selected)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            .padding(8)
            Divider()
            List(selection: $session.selectedEventId) {
                OutlineGroup(EventNode.tree(session.events), children: \.children) { node in
                    EventRow(event: node.event)
                        .tag(node.event.id)
                        .contextMenu {
                            Button("New sub-event…") { editor = EventEditorState(parentId: node.event.id) }
                            Button("Edit…") { editor = EventEditorState(editing: node.event) }
                            Menu("Move under") {
                                Button("Top level") { session.moveEvent(node.event, to: nil) }
                                ForEach(session.events.filter { $0.id != node.event.id }) { other in
                                    Button(session.eventPathName(other.id) ?? other.name) { session.moveEvent(node.event, to: other.id) }
                                }
                            }
                            Divider()
                            Button("Delete (photos become unassigned)", role: .destructive) { session.deleteEvent(node.event) }
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            session.assign(clusters: Set(ids), to: node.event.id)
                            return true
                        }
                }
            }
            .listStyle(.sidebar)
            Divider()
            Text("Select an event, then use “Assign” on a group, or drag a group onto an event. Right-click an event to add sub-events (e.g. Asia Trip ▸ Hong Kong ▸ Temples).")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
        }
        .sheet(item: $editor) { state in
            EventEditorSheet(session: session, state: state)
        }
    }
}

private struct EventRow: View {
    let event: PhotoEvent
    private static let formatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateTemplate = "d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(event.name).lineLimit(1)
                Spacer()
                Text("\(event.photoCount)").font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
            if let start = event.startDate, let end = event.endDate {
                Text(Self.formatter.string(from: start, to: end) + (event.place.map { " · \($0)" } ?? ""))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }

    private var icon: String {
        switch event.kind {
        case "trip": return "airplane"
        case "place": return "mappin.and.ellipse"
        case "subject": return "camera.macro"
        default: return "calendar"
        }
    }
}

struct EventEditorState: Identifiable {
    let id = UUID()
    var parentId: Int64?
    var editing: PhotoEvent?
    var name = ""
    var kind = "event"
    var place = ""
    /// Shots to assign once created (from "Name this group").
    var assignShots: [Shot] = []

    init(parentId: Int64?, name: String = "", kind: String = "event", place: String = "", assignShots: [Shot] = []) {
        self.parentId = parentId
        self.name = name
        self.kind = kind
        self.place = place
        self.assignShots = assignShots
    }

    init(editing event: PhotoEvent) {
        self.editing = event
        self.parentId = event.parentId
        self.name = event.name
        self.kind = event.kind
        self.place = event.place ?? ""
    }
}

private struct EventEditorSheet: View {
    @ObservedObject var session: OrganizeSession
    @State var state: EventEditorState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.editing == nil ? "New event" : "Edit event").font(.title2).bold()
            if !state.assignShots.isEmpty {
                Text("\(state.assignShots.count) shots will be filed under it.").foregroundColor(.secondary)
            }
            TextField("Name (e.g. Asia Trip, Hong Kong, Temples)", text: $state.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
            Picker("Kind", selection: $state.kind) {
                Text("Trip").tag("trip")
                Text("Event").tag("event")
                Text("Place").tag("place")
                Text("Subject").tag("subject")
            }
            .pickerStyle(.segmented)
            TextField("Place (optional)", text: $state.place)
                .textFieldStyle(.roundedBorder)
            Picker("Inside", selection: $state.parentId) {
                Text("Top level").tag(Int64?.none)
                ForEach(session.events.filter { $0.id != state.editing?.id }) { e in
                    Text(session.eventPathName(e.id) ?? e.name).tag(Optional(e.id))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(state.editing == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func save() {
        let name = state.name.trimmingCharacters(in: .whitespaces)
        let place = state.place.trimmingCharacters(in: .whitespaces)
        if let event = state.editing {
            session.renameEvent(event, name: name, kind: state.kind, place: place.isEmpty ? nil : place)
            if event.parentId != state.parentId { session.moveEvent(event, to: state.parentId) }
        } else if let id = session.createEvent(name: name, parentId: state.parentId, kind: state.kind, place: place.isEmpty ? nil : place),
                  !state.assignShots.isEmpty {
            session.assign(shots: state.assignShots, to: id)
        }
        dismiss()
    }
}

private struct ClusterTimeline: View {
    @ObservedObject var session: OrganizeSession
    @Binding var detailCluster: ShotCluster?
    @State private var editor: EventEditorState?

    private var visible: [ShotCluster] {
        session.showAssigned ? session.clusters : session.clusters.filter { $0.unassignedCount > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Show groups that are already filed", isOn: $session.showAssigned)
                Spacer()
                if !session.selectedClusterIds.isEmpty {
                    Text("\(session.selectedClusterIds.count) selected").foregroundColor(.secondary)
                    Button("Assign to \(session.eventMap[session.selectedEventId ?? -1]?.name ?? "selected event")") {
                        session.assign(clusters: session.selectedClusterIds, to: session.selectedEventId)
                        session.selectedClusterIds = []
                    }
                    .disabled(session.selectedEventId == nil)
                    Button("New event from selection…") {
                        let shots = session.allClusters.filter { session.selectedClusterIds.contains($0.id) }.flatMap(\.shots)
                        editor = EventEditorState(parentId: session.selectedEventId, assignShots: Array(Set(shots)))
                    }
                    Button("Clear") { session.selectedClusterIds = [] }
                }
            }
            .padding(8)
            Divider()
            if session.clusters.isEmpty {
                ContentUnavailableView("Nothing analysed yet", systemImage: "sparkle.magnifyingglass",
                                       description: Text("Run step 1 first."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(yearSections, id: \.year) { section in
                            Section {
                                ForEach(section.clusters) { cluster in
                                    ClusterCard(session: session, cluster: cluster, detailCluster: $detailCluster, editor: $editor)
                                }
                            } header: {
                                Text(section.year).font(.title3).bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(.bar)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(item: $editor) { state in
            EventEditorSheet(session: session, state: state)
        }
    }

    private var yearSections: [(year: String, clusters: [ShotCluster])] {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        let grouped = Dictionary(grouping: visible) { $0.kind == .undated ? "Undated" : f.string(from: $0.start) }
        return grouped.map { ($0.key, $0.value) }.sorted { lhs, rhs in
            if lhs.year == "Undated" { return false }
            if rhs.year == "Undated" { return true }
            return lhs.year < rhs.year
        }
    }
}

private struct ClusterCard: View {
    @ObservedObject var session: OrganizeSession
    let cluster: ShotCluster
    @Binding var detailCluster: ShotCluster?
    @Binding var editor: EventEditorState?
    var indent: CGFloat = 0
    @State private var expanded = true

    private var isSelected: Bool { session.selectedClusterIds.contains(cluster.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Filmstrip(shots: cluster.shots)
                .onTapGesture(count: 2) { detailCluster = cluster }
            if cluster.kind == .trip {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cluster.children) { child in
                            ClusterCard(session: session, cluster: child, detailCluster: $detailCluster, editor: $editor, indent: 16)
                        }
                    }
                } label: {
                    Text("\(cluster.children.count) sessions").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .padding(.leading, indent)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(cluster.kind == .trip ? 0.10 : 0.05))
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                if isSelected { session.selectedClusterIds.remove(cluster.id) } else { session.selectedClusterIds.insert(cluster.id) }
            } else {
                session.selectedClusterIds = isSelected ? [] : [cluster.id]
            }
        }
        .draggable(cluster.id)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: cluster.kind == .trip ? "airplane" : cluster.kind == .undated ? "questionmark.folder" : "clock")
                .foregroundColor(cluster.kind == .trip ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(OrganizeEngine.suggestedName(for: cluster)).font(.headline)
                HStack(spacing: 10) {
                    Text("\(cluster.shots.count) shots · \(cluster.fileCount) files")
                    if cluster.days > 1 { Text("\(cluster.days) days") }
                    if !cluster.cameras.isEmpty { Text(cluster.cameras.prefix(3).joined(separator: ", ")) }
                }
                .font(.caption).foregroundColor(.secondary)
                assignmentBadge
            }
            Spacer()
            Button("Name…") {
                editor = EventEditorState(parentId: session.selectedEventId,
                                          name: cluster.kind == .undated ? "" : OrganizeEngine.suggestedName(for: cluster),
                                          kind: cluster.kind == .trip ? "trip" : "event",
                                          place: cluster.place ?? "",
                                          assignShots: cluster.shots)
            }
            .help("Create an event for this group (inside the selected event, if any)")
            Button("Assign") { session.assign(shots: cluster.shots, to: session.selectedEventId) }
                .disabled(session.selectedEventId == nil)
                .help("File this group under the event selected on the left")
            Button {
                detailCluster = cluster
            } label: {
                Image(systemName: "rectangle.grid.3x2")
            }
            .help("Open to pick a subset, split it or tag people")
        }
    }

    @ViewBuilder private var assignmentBadge: some View {
        let assigned = cluster.assignedEvents
        if !assigned.isEmpty {
            let names = assigned.sorted { $0.value > $1.value }.prefix(3).compactMap { session.eventPathName($0.key) }
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").foregroundColor(.green)
                Text(names.joined(separator: "; "))
                if cluster.unassignedCount > 0 {
                    Text("(\(cluster.unassignedCount) not filed)").foregroundColor(.orange)
                }
            }
            .font(.caption)
        }
    }
}

/// A row of evenly spaced representative thumbnails.
private struct Filmstrip: View {
    let shots: [Shot]
    var size: CGFloat = 84
    var maxCount = 14

    var body: some View {
        let picks = Self.sample(shots, maxCount)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(picks) { shot in
                    AsyncThumbnail(photo: shot.primary, size: size)
                        .cornerRadius(4)
                        .overlay(alignment: .bottomTrailing) { ShotBadges(shot: shot) }
                }
                if shots.count > picks.count {
                    Text("+\(shots.count - picks.count)")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 50, height: size)
                }
            }
        }
    }

    static func sample(_ shots: [Shot], _ n: Int) -> [Shot] {
        guard shots.count > n else { return shots }
        return (0..<n).map { shots[$0 * (shots.count - 1) / (n - 1)] }
    }
}

private struct ShotBadges: View {
    let shot: Shot
    var body: some View {
        HStack(spacing: 2) {
            if shot.keepers.contains(where: { $0.mediaKind == .raw }) { badge("RAW") }
            if !shot.duplicates.isEmpty { badge("×\(shot.duplicates.count + 1)") }
            if shot.hasNearDuplicates { badge("≈") }
        }
        .padding(2)
    }
    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .bold)).padding(.horizontal, 3)
            .background(Capsule().fill(.black.opacity(0.6))).foregroundColor(.white)
    }
}

private struct ClusterDetailSheet: View {
    @ObservedObject var session: OrganizeSession
    let cluster: ShotCluster
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var lastClicked: Int?
    @State private var peopleText = ""
    @State private var editor: EventEditorState?
    @State private var thumbSize: CGFloat = 130

    private var shots: [Shot] {
        // Fresh copies so assignments made in this sheet show immediately.
        let ids = Set(cluster.shots.map(\.id))
        return session.shots.filter { ids.contains($0.id) }
    }
    private var selectedShots: [Shot] { shots.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(OrganizeEngine.suggestedName(for: cluster)).font(.title2).bold()
                    Text("Click to select, shift-click for a range, ⌘-click to add. Select the shots that belong together (e.g. the temple visit) and file them.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Slider(value: $thumbSize, in: 80...260).frame(width: 140)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize), spacing: 6)], spacing: 6) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                        VStack(spacing: 2) {
                            AsyncThumbnail(photo: shot.primary, size: thumbSize)
                                .cornerRadius(4)
                                .overlay(alignment: .bottomTrailing) { ShotBadges(shot: shot) }
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(selection.contains(shot.id) ? Color.accentColor : .clear, lineWidth: 3))
                            Text(session.eventPathName(shot.primary.eventId)?.components(separatedBy: " ▸ ").last ?? shot.primary.fileName)
                                .font(.caption2).lineLimit(1).foregroundColor(shot.primary.eventId == nil ? .secondary : .green)
                        }
                        .frame(width: thumbSize)
                        .contentShape(Rectangle())
                        .onTapGesture { click(index) }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Text("\(selection.count) selected").foregroundColor(.secondary)
                Button("Select all") { selection = Set(shots.map(\.id)) }
                Button("Select from here to end") {
                    if let start = lastClicked { selection = Set(shots[start...].map(\.id)) }
                }
                .disabled(lastClicked == nil)
                Spacer()
                Button("New sub-event…") {
                    editor = EventEditorState(parentId: session.selectedEventId ?? dominantEvent, place: cluster.place ?? "", assignShots: selectedShots)
                }
                .disabled(selection.isEmpty)
                Button("Assign to \(session.eventMap[session.selectedEventId ?? -1]?.name ?? "selected event")") {
                    session.assign(shots: selectedShots, to: session.selectedEventId)
                }
                .disabled(selection.isEmpty || session.selectedEventId == nil)
                Button("Unassign") { session.assign(shots: selectedShots, to: nil) }
                    .disabled(selection.isEmpty)
                TextField("People (comma separated)", text: $peopleText)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                Button("Tag") {
                    session.tagPeople(DatabaseManager.splitTags(peopleText), on: selectedShots)
                    peopleText = ""
                }
                .disabled(selection.isEmpty || peopleText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
        .sheet(item: $editor) { state in
            EventEditorSheet(session: session, state: state)
        }
    }

    /// The event most of this cluster is filed under, as the default parent for new sub-events.
    private var dominantEvent: Int64? {
        cluster.assignedEvents.max { $0.value < $1.value }?.key
    }

    private func click(_ index: Int) {
        let id = shots[index].id
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let last = lastClicked {
            let range = min(last, index)...max(last, index)
            selection.formUnion(shots[range].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = selection == [id] ? [] : [id]
        }
        lastClicked = index
    }
}

// MARK: - Step 3: Near-copies

private struct NearDuplicateStepView: View {
    @ObservedObject var session: OrganizeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Near-copies").font(.title2).bold()
                Text("These shots have more than one version of the same kind with different bytes: usually a resized export, an edit or a re-saved copy. Exact duplicates are already handled (one copy is kept). By default every version is copied; choose “Keep best” to copy only the largest.")
                    .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Keep only the best version for all of these", isOn: $session.layout.keepBestNearDuplicate)
            }
            .padding()
            Divider()
            if session.nearDuplicateShots.isEmpty {
                ContentUnavailableView("No near-copies", systemImage: "checkmark.seal")
            } else {
                List(session.nearDuplicateShots) { shot in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(shot.keepers, id: \.id) { file in
                            VStack(alignment: .leading, spacing: 2) {
                                AsyncThumbnail(photo: file, size: 110).cornerRadius(4)
                                Text(file.fileName).font(.caption).lineLimit(1)
                                Text("\(file.imageWidth ?? 0)×\(file.imageHeight ?? 0) · \(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))")
                                    .font(.caption2).foregroundColor(.secondary)
                                Text(file.directoryPath).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            .frame(width: 130)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { session.layout.nearDuplicateDecisions[shot.id] ?? session.layout.keepBestNearDuplicate },
                            set: { session.layout.nearDuplicateDecisions[shot.id] = $0 })) {
                            Text("Keep all").tag(false)
                            Text("Keep best").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Spacer()
                Button("Next: plan") { session.step = .plan }.buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// MARK: - Step 4: Plan

private struct PlanStepView: View {
    @ObservedObject var session: OrganizeSession
    @State private var pickingTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan the new library").font(.title2).bold()
            Text("Files are copied into the folder you choose as Year / dated event / sub-events, with RAW files in a RAW subfolder next to their JPEGs. Photos not filed under an event go to Year / Year-Month Unsorted; photos without a trustworthy date go to Undated / <original folder>. Your current folders are not changed.")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Choose target folder…") { pickingTarget = true }
                if let url = session.targetURL {
                    Text(url.path).font(.callout).lineLimit(1).truncationMode(.middle)
                    if isInsideLibrary(url) {
                        Label("This folder is inside a library root; choose a separate folder or drive.", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange).font(.caption)
                    }
                }
                Spacer()
                Button("Build plan") { session.buildPlan() }
                    .disabled(session.shots.isEmpty)
            }
            if !session.planEntries.isEmpty {
                Text(session.planSummary.text).font(.callout)
                HSplitView {
                    List(session.planFolders, id: \.folder) { item in
                        HStack {
                            Image(systemName: item.folder.hasSuffix("/RAW") ? "camera.aperture" : "folder")
                            Text(item.folder).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text("\(item.count)").foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                    .frame(minWidth: 400)
                    List(session.planEntries.filter { $0.action == .skip }.prefix(2000), id: \.self) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.photo.relativePath).lineLimit(1).truncationMode(.middle)
                            Text("skip: \(entry.reason)").font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .frame(minWidth: 300)
                }
                HStack {
                    Toggle("Write XMP sidecars with events, people, keywords and ratings (for Lightroom, Bridge, Photos)", isOn: $session.writeSidecars)
                    Spacer()
                    Button("Copy \(session.planSummary.copyFiles) files…") { session.saveAndRunPlan() }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.targetURL == nil || session.targetURL.map(isInsideLibrary) == true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .fileImporter(isPresented: $pickingTarget, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                session.targetURL = url
            }
        }
    }

    private func isInsideLibrary(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return session.library.rootDirectories.contains { root in
            let r = (root.path as NSString).standardizingPath
            return path == r || path.hasPrefix(r + "/") || r.hasPrefix(path + "/")
        }
    }
}

// MARK: - Step 5: Copy

private struct CopyStepView: View {
    @ObservedObject var session: OrganizeSession
    @State private var confirmTrash = false
    @State private var includeNear = false
    @State private var trashSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Copy").font(.title2).bold()
            let p = session.executorProgress
            ProgressView(value: p.fraction) {
                Text("\(p.done) of \(p.total) files" + (p.failed > 0 ? " · \(p.failed) failed" : ""))
            } currentValueLabel: {
                Text(p.current).lineLimit(1).truncationMode(.middle)
            }
            if let outcome = session.outcome {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(outcome.verified) files copied and verified" + (outcome.alreadyPresent > 0 ? " (\(outcome.alreadyPresent) were already there)" : ""),
                              systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        if !outcome.failed.isEmpty {
                            Label("\(outcome.failed.count) failed (nothing was overwritten). Fix the cause and press Resume.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            ForEach(outcome.failed.prefix(8), id: \.0) { failure in
                                Text("\(failure.0): \(failure.1)").font(.caption).lineLimit(2)
                            }
                            Button("Resume") { session.runPlan() }
                        }
                        if let sidecars = session.sidecarSummary {
                            Label(sidecars, systemImage: "tag").font(.callout)
                        }
                        if let manifest = outcome.manifestPath {
                            HStack {
                                Text("Manifest: \(manifest)").font(.caption).lineLimit(1).truncationMode(.middle)
                                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: manifest)]) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                GroupBox("Next") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Add the new folder to the library so it is catalogued and searchable.")
                            Spacer()
                            Button("Add to library") { session.addTargetToLibrary() }
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Move the originals to the Trash: only files whose content now has a verified copy in the new folder (copied files and their exact duplicates).")
                                Toggle("Also trash near-copies that were skipped", isOn: $includeNear)
                            }
                            Spacer()
                            Button("Move originals to Trash…") { confirmTrash = true }
                                .disabled(!outcome.failed.isEmpty)
                        }
                        if let trashSummary { Text(trashSummary).font(.caption).foregroundColor(.secondary) }
                    }
                    .padding(6)
                }
            }
            Spacer()
        }
        .padding()
        .confirmationDialog("Move the originals to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) {
                trashSummary = session.trashOriginals(includeNearDuplicates: includeNear)?.summary
            }
        } message: {
            Text("Every file moved has a byte-for-byte verified copy in \(session.targetURL?.path ?? "the target"). You can restore them from the Trash.")
        }
    }
}
