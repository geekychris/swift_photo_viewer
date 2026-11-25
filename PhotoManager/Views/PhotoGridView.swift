import SwiftUI
import os.log
import AppKit

private let logger = Logger(subsystem: "com.photomarger", category: "photogrid")

enum ContactSheetFormat {
    case html
    case pdf
}

struct ContactSheetOptions: Equatable {
    var format: ContactSheetFormat
    var includeFilePath: Bool = true
    var includeFileName: Bool = true
    var includeDate: Bool = true
    var includeDimensions: Bool = true
    var includeFileSize: Bool = true
    var includeCamera: Bool = true
    var includeLens: Bool = true
    var includeExposure: Bool = true
    var includeDescription: Bool = true
    var includeTags: Bool = true
}

struct ContactSheetOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let format: ContactSheetFormat
    let photoCount: Int
    let onGenerate: (ContactSheetOptions) -> Void

    @State private var localOptions: ContactSheetOptions

    init(format: ContactSheetFormat, photoCount: Int, onGenerate: @escaping (ContactSheetOptions) -> Void) {
        self.format = format
        self.photoCount = photoCount
        self.onGenerate = onGenerate
        self._localOptions = State(initialValue: ContactSheetOptions(format: format))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Contact Sheet Options")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            // Options
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select metadata to include in \(format == .html ? "HTML" : "PDF") contact sheet (\(photoCount) photos):")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("File Path", isOn: $localOptions.includeFilePath)
                        Toggle("File Name", isOn: $localOptions.includeFileName)
                        Toggle("Date Taken", isOn: $localOptions.includeDate)
                        Toggle("Image Dimensions", isOn: $localOptions.includeDimensions)
                        Toggle("File Size", isOn: $localOptions.includeFileSize)
                        Toggle("Camera Model", isOn: $localOptions.includeCamera)
                        Toggle("Lens Model", isOn: $localOptions.includeLens)
                        Toggle("Exposure Settings (Aperture, Shutter, ISO, Focal Length)", isOn: $localOptions.includeExposure)
                        Toggle("User Description", isOn: $localOptions.includeDescription)
                        Toggle("User Tags", isOn: $localOptions.includeTags)
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    HStack {
                        Button("Select All") { setAll(true) }
                            .buttonStyle(.bordered)

                        Button("Deselect All") { setAll(false) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate") {
                    onGenerate(localOptions)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func setAll(_ on: Bool) {
        localOptions.includeFilePath = on
        localOptions.includeFileName = on
        localOptions.includeDate = on
        localOptions.includeDimensions = on
        localOptions.includeFileSize = on
        localOptions.includeCamera = on
        localOptions.includeLens = on
        localOptions.includeExposure = on
        localOptions.includeDescription = on
        localOptions.includeTags = on
    }
}

// MARK: - Destination Picker View

struct DestinationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoLibrary: PhotoLibrary

    let operationType: OperationType
    let photoCount: Int
    let onSelect: (Destination) -> Void

    @State private var showingFilePicker = false
    @State private var selectedDirectory: RootDirectory?

    enum OperationType {
        case copy
        case move

        var title: String {
            switch self {
            case .copy: return "Copy"
            case .move: return "Move"
            }
        }

        var kind: FileOperationKind {
            self == .copy ? .copy : .move
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(operationType.title) \(photoCount) photo\(photoCount == 1 ? "" : "s")")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Select destination:").font(.headline)

                if !photoLibrary.rootDirectories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Managed Directories").font(.subheadline).foregroundColor(.secondary)

                        ForEach(photoLibrary.rootDirectories) { directory in
                            Button {
                                selectedDirectory = directory
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill").foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(directory.name).fontWeight(.medium)
                                        Text(directory.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedDirectory?.id == directory.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                    }
                                }
                                .padding(12)
                                .background(selectedDirectory?.id == directory.id ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().padding(.vertical, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Location").font(.subheadline).foregroundColor(.secondary)
                    Button { showingFilePicker = true } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus").foregroundColor(.green)
                            Text("Choose a folder...").fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(operationType.title) {
                    if let directory = selectedDirectory {
                        onSelect(.managedDirectory(directory))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDirectory == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                // FileOperationService holds security-scoped access to this URL while it works.
                onSelect(.unmanagedURL(url))
                dismiss()
            }
        }
    }
}

// MARK: - Photo actions (open, contact sheet, copy/move, batch rating)

/// Runs context-menu actions for a grid. Lives above the cells so results survive cells
/// disappearing after a move, and resolves photo ids from the database off the main thread.
final class PhotoActionCenter: ObservableObject {
    struct DestinationRequest: Identifiable {
        let id = UUID()
        let operation: DestinationPickerView.OperationType
        let ids: [Int64]
    }

    struct ContactSheetRequest: Identifiable {
        let id = UUID()
        let format: ContactSheetFormat
        let ids: [Int64]
    }

    @Published var destinationRequest: DestinationRequest?
    @Published var contactSheetRequest: ContactSheetRequest?
    @Published var message = ""
    @Published var showingMessage = false
    @Published var workingMessage: String?

    func requestFileOperation(_ operation: DestinationPickerView.OperationType, ids: [Int64]) {
        guard !ids.isEmpty else { return }
        destinationRequest = DestinationRequest(operation: operation, ids: ids)
    }

    func requestContactSheet(_ format: ContactSheetFormat, ids: [Int64]) {
        guard !ids.isEmpty else { return }
        contactSheetRequest = ContactSheetRequest(format: format, ids: ids)
    }

    private func resolve(_ ids: [Int64], library: PhotoLibrary) async -> [PhotoFile] {
        let db = library.databaseManager
        return await Task.detached(priority: .userInitiated) { (try? db.photos(withIds: ids)) ?? [] }.value
    }

    private func report(_ text: String) {
        workingMessage = nil
        message = text
        showingMessage = true
    }

    @MainActor
    func open(ids: [Int64], library: PhotoLibrary) {
        Task {
            let photos = await resolve(ids, library: library)
            for photo in photos {
                guard let root = library.rootDirectory(id: photo.rootDirectoryId) else { continue }
                let url = URL(fileURLWithPath: (root.path as NSString).appendingPathComponent(photo.relativePath))
                SecurityScope.withAccess(root) { _ = NSWorkspace.shared.open(url) }
            }
        }
    }

    @MainActor
    func setRating(_ rating: Int, ids: [Int64], library: PhotoLibrary) {
        let db = library.databaseManager
        Task {
            do {
                try await Task.detached { try db.updateRating(photoIds: ids, rating: rating) }.value
                library.libraryDidChange(refreshDuplicates: false)
            } catch {
                logger.error("Batch rating failed: \(error.localizedDescription, privacy: .public)")
                library.errorMessage = "Failed to update ratings: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    func setColorTag(_ colorTag: String?, ids: [Int64], library: PhotoLibrary) {
        let db = library.databaseManager
        Task {
            do {
                try await Task.detached { try db.updateColorTag(photoIds: ids, colorTag: colorTag) }.value
                library.libraryDidChange(refreshDuplicates: false)
            } catch {
                logger.error("Batch colour tag failed: \(error.localizedDescription, privacy: .public)")
                library.errorMessage = "Failed to update colour tags: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    func performFileOperation(_ request: DestinationRequest, to destination: Destination, library: PhotoLibrary) {
        let kind = request.operation.kind
        let count = request.ids.count
        workingMessage = "\(kind == .copy ? "Copying" : "Moving") \(count) file\(count == 1 ? "" : "s")..."
        let roots = library.rootDirectories
        let service = FileOperationService(databaseManager: library.databaseManager)
        Task {
            let photos = await resolve(request.ids, library: library)
            let result = await Task.detached(priority: .userInitiated) {
                await service.perform(kind, photos: photos, to: destination, roots: roots)
            }.value
            if !result.succeeded.isEmpty {
                library.libraryDidChange()
            }
            report(result.summary)
        }
    }

    @MainActor
    func generateContactSheet(ids: [Int64], options: ContactSheetOptions, library: PhotoLibrary) {
        workingMessage = "Generating contact sheet..."
        let roots = library.rootDirectories
        Task {
            let photos = await resolve(ids, library: library)
            let thumbnail: (PhotoFile) -> NSImage? = { library.getThumbnailImage(for: $0) }
            let outcome: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                Result { try ContactSheetGenerator.generate(photos: photos, roots: roots, options: options, thumbnail: thumbnail) }
            }.value
            switch outcome {
            case .success(let url):
                workingMessage = nil
                NSWorkspace.shared.open(url)
            case .failure(let error):
                logger.error("Contact sheet failed: \(error.localizedDescription, privacy: .public)")
                report("Failed to generate contact sheet: \(error.localizedDescription)")
            }
        }
    }
}

/// Attaches the sheets and alerts that `PhotoActionCenter` drives.
struct PhotoActionsHost: ViewModifier {
    @ObservedObject var center: PhotoActionCenter
    @EnvironmentObject var photoLibrary: PhotoLibrary

    func body(content: Content) -> some View {
        content
            .environmentObject(center)
            .sheet(item: $center.destinationRequest) { request in
                DestinationPickerView(operationType: request.operation, photoCount: request.ids.count) { destination in
                    center.performFileOperation(request, to: destination, library: photoLibrary)
                }
                .environmentObject(photoLibrary)
            }
            .sheet(item: $center.contactSheetRequest) { request in
                ContactSheetOptionsView(format: request.format, photoCount: request.ids.count) { options in
                    center.generateContactSheet(ids: request.ids, options: options, library: photoLibrary)
                }
            }
            .alert(center.message, isPresented: $center.showingMessage) {
                Button("OK") { }
            }
            .overlay(alignment: .bottom) {
                if let working = center.workingMessage {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(working).font(.caption)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding()
                }
            }
    }
}

extension View {
    func photoActions(_ center: PhotoActionCenter) -> some View {
        modifier(PhotoActionsHost(center: center))
    }
}

// MARK: - Grid

struct PhotoGridView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedPhoto: PhotoFile?
    let filterDirectoryId: Int64?
    /// A folder relative to the root (with its subfolders), or "" for files directly in the root.
    let filterSubdirectoryPath: String?
    /// Timeline period key ("2019", "2019-03", "2019-03-12", "2019-W10").
    var filterPeriod: String? = nil

    private static let pageSize = 200

    @StateObject private var actions = PhotoActionCenter()
    @State private var photos: [PhotoFile] = []
    @State private var totalCount = 0
    @State private var isLoadingPage = false
    @State private var generation = 0
    @State private var thumbnailSize: CGFloat = 200
    @State private var selectedPhotoIds: Set<Int64> = []
    @State private var isSelectionMode: Bool = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }

    private var filter: PhotoFilter {
        var filter = filterPeriod.map(PhotoFilter.forPeriod) ?? PhotoFilter()
        if let rootId = filterDirectoryId {
            filter.rootDirectoryId = rootId
            if let path = filterSubdirectoryPath {
                filter.directoryPath = path
                // "" means the files directly in the root; any other folder includes its subfolders.
                filter.includeSubdirectories = !path.isEmpty
            }
        }
        return filter
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack {
                // Selection mode toggle
                Button {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedPhotoIds.removeAll()
                    }
                } label: {
                    Label(isSelectionMode ? "Cancel" : "Select", systemImage: isSelectionMode ? "xmark.circle" : "checkmark.circle")
                }
                .buttonStyle(.bordered)

                if isSelectionMode {
                    Button("Select All") {
                        selectAllMatching()
                    }
                    .buttonStyle(.bordered)

                    Button("Deselect All") {
                        selectedPhotoIds.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPhotoIds.isEmpty)

                    Text("\(selectedPhotoIds.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(totalCount) photo\(totalCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)

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

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("grid-top")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(photos) { photo in
                            PhotoThumbnailView(
                                photo: photo,
                                thumbnailSize: thumbnailSize,
                                isSelectionMode: isSelectionMode,
                                isSelected: photo.id.map { selectedPhotoIds.contains($0) } ?? false,
                                onTap: {
                                    if isSelectionMode {
                                        if let photoId = photo.id {
                                            if selectedPhotoIds.contains(photoId) {
                                                selectedPhotoIds.remove(photoId)
                                            } else {
                                                selectedPhotoIds.insert(photoId)
                                            }
                                        }
                                    } else {
                                        selectedPhoto = photo
                                    }
                                },
                                selectedPhotoIds: $selectedPhotoIds
                            )
                            .onAppear {
                                if photo.id == photos.last?.id {
                                    loadNextPage()
                                }
                            }
                        }

                        // Loading indicator
                        if photos.count < totalCount {
                            ProgressView()
                                .frame(width: 200, height: 200)
                                .onAppear {
                                    loadNextPage()
                                }
                        }
                    }
                    .padding()
                }
                .onChange(of: filter) {
                    proxy.scrollTo("grid-top", anchor: .top)
                }
            }
        }
        .photoActions(actions)
        .task(id: filter) {
            selectedPhotoIds.removeAll()
            await reload(keepLoaded: false)
        }
        .onChange(of: photoLibrary.libraryVersion) {
            Task { await reload(keepLoaded: true) }
        }
    }

    /// Reloads from the first row. With `keepLoaded`, re-reads as many rows as are loaded now
    /// so the scroll position survives catalogue changes.
    private func reload(keepLoaded: Bool) async {
        generation += 1
        let gen = generation
        let filter = self.filter
        let limit = keepLoaded ? max(photos.count, Self.pageSize) : Self.pageSize
        let db = photoLibrary.databaseManager
        if !keepLoaded {
            photos = []
            totalCount = 0
        }
        isLoadingPage = true
        let (page, count) = await Task.detached(priority: .userInitiated) { () -> ([PhotoFile], Int) in
            do {
                let count = try db.countPhotos(matching: filter).count
                let page = try db.photos(matching: filter, sort: .captureDescending, limit: limit, offset: 0)
                return (page, count)
            } catch {
                logger.error("Grid query failed: \(error.localizedDescription, privacy: .public)")
                return ([], 0)
            }
        }.value
        guard gen == generation else { return }
        photos = page
        totalCount = count
        isLoadingPage = false
    }

    private func loadNextPage() {
        guard !isLoadingPage, photos.count < totalCount else { return }
        isLoadingPage = true
        let gen = generation
        let filter = self.filter
        let offset = photos.count
        let db = photoLibrary.databaseManager
        Task {
            let page = await Task.detached(priority: .userInitiated) {
                (try? db.photos(matching: filter, sort: .captureDescending, limit: Self.pageSize, offset: offset)) ?? []
            }.value
            guard gen == generation else { return }
            // Rows may have moved between pages if the catalogue changed; never show one twice.
            let known = Set(photos.compactMap(\.id))
            photos.append(contentsOf: page.filter { $0.id.map { !known.contains($0) } ?? true })
            if page.isEmpty { totalCount = photos.count }
            isLoadingPage = false
        }
    }

    private func selectAllMatching() {
        let filter = self.filter
        let db = photoLibrary.databaseManager
        Task {
            let ids = await Task.detached(priority: .userInitiated) { (try? db.photoIds(matching: filter)) ?? [] }.value
            selectedPhotoIds = Set(ids)
        }
    }
}

// MARK: - Rating Label Component
struct RatingPickerLabel: View {
    let rating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<rating, id: \.self) { _ in
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Color Tag Indicator Component
struct ColorTagIndicator: View {
    let colorTag: String?
    var size: CGFloat = 12
    
    private func colorForTag(_ tag: String) -> Color? {
        switch tag {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray": return .gray
        default: return nil
        }
    }
    
    var body: some View {
        if let colorTag = colorTag,
           let color = colorForTag(colorTag) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: PhotoFile
    let thumbnailSize: CGFloat
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    var selectedPhotoIds: Binding<Set<Int64>>? = nil
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @EnvironmentObject var actions: PhotoActionCenter
    @State private var isHovering: Bool = false
    @State private var rating: Int = 0
    @State private var colorTag: String? = nil

    private var quickColors: [(id: String, color: Color)] {
        [
            ("red", .red),
            ("orange", .orange),
            ("yellow", .yellow),
            ("green", .green),
            ("blue", .blue),
            ("purple", .purple),
            ("gray", .gray)
        ]
    }

    /// What a context-menu action applies to: the selection if this photo is part of it, otherwise this photo only.
    private var targetIds: [Int64] {
        guard let id = photo.id else { return [] }
        if let selection = selectedPhotoIds?.wrappedValue, selection.contains(id) {
            return Array(selection)
        }
        return [id]
    }

    @ViewBuilder
    private var thumbnailDisplay: some View {
        AsyncThumbnail(photo: photo, size: thumbnailSize, contentMode: .fit)
            .cornerRadius(8)
    }

    @ViewBuilder
    private var hoverControls: some View {
        if isHovering && !isSelectionMode {
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { index in
                            Button {
                                let newRating = rating == index ? 0 : index
                                rating = newRating
                                if let photoId = photo.id {
                                    photoLibrary.updatePhotoRating(photoId, rating: newRating)
                                }
                            } label: {
                                Image(systemName: index <= rating ? "flag.fill" : "flag")
                                    .foregroundColor(index <= rating ? .orange : .white.opacity(0.7))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)

                    HStack(spacing: 4) {
                        Button {
                            colorTag = nil
                            if let photoId = photo.id {
                                photoLibrary.updatePhotoColorTag(photoId, colorTag: nil)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)

                        ForEach(quickColors, id: \.id) { option in
                            Button {
                                let newColor = colorTag == option.id ? nil : option.id
                                colorTag = newColor
                                if let photoId = photo.id {
                                    photoLibrary.updatePhotoColorTag(photoId, colorTag: newColor)
                                }
                            } label: {
                                ZStack {
                                    Rectangle().fill(Color.clear).frame(width: 24, height: 24)
                                    Circle().fill(option.color).frame(width: 16, height: 16)
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                                        .overlay(colorTag == option.id ? Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white) : nil)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                }
                .padding(8)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail with overlay controls
            ZStack {
                thumbnailDisplay

                // Selection indicator
                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(isSelected ? .blue : .white)
                            }
                            .padding(8)
                        }
                        Spacer()
                    }
                }

                hoverControls
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .contextMenu {
                if photo.id != nil {
                    let ids = targetIds
                    Button {
                        actions.open(ids: ids, library: photoLibrary)
                    } label: {
                        Label(ids.count > 1 ? "Open \(ids.count) Photos" : "Open", systemImage: "arrow.up.forward.app")
                    }

                    Divider()

                    Menu("Rating") {
                        ForEach(0...5, id: \.self) { value in
                            Button(value == 0 ? "No Flags" : String(repeating: "⚑", count: value)) {
                                actions.setRating(value, ids: ids, library: photoLibrary)
                                if ids.count == 1 { rating = value }
                            }
                        }
                    }

                    Menu("Colour") {
                        Button("None") {
                            actions.setColorTag(nil, ids: ids, library: photoLibrary)
                            if ids.count == 1 { colorTag = nil }
                        }
                        ForEach(quickColors, id: \.id) { option in
                            Button(option.id.capitalized) {
                                actions.setColorTag(option.id, ids: ids, library: photoLibrary)
                                if ids.count == 1 { colorTag = option.id }
                            }
                        }
                    }

                    Divider()

                    Menu("Contact Sheet") {
                        Button {
                            actions.requestContactSheet(.html, ids: ids)
                        } label: {
                            Label("HTML", systemImage: "doc.richtext")
                        }

                        Button {
                            actions.requestContactSheet(.pdf, ids: ids)
                        } label: {
                            Label("PDF", systemImage: "doc.fill")
                        }
                    }

                    Divider()

                    Button {
                        actions.requestFileOperation(.copy, ids: ids)
                    } label: {
                        Label("Copy to...", systemImage: "doc.on.doc")
                    }

                    Button {
                        actions.requestFileOperation(.move, ids: ids)
                    } label: {
                        Label("Move to...", systemImage: "folder")
                    }
                }
            }

            // Photo info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Date and dimensions
                HStack {
                    if let dateTaken = photo.exifDateTaken {
                        Text(dateTaken, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let width = photo.imageWidth, let height = photo.imageHeight {
                        Text("\(width)×\(height)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Camera model
                if let cameraModel = photo.exifCameraModel {
                    Text(cameraModel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Exposure details
                if photo.exifAperture != nil || photo.exifShutterSpeed != nil || photo.exifIso != nil || photo.exifFocalLength != nil {
                    HStack(spacing: 4) {
                        if let aperture = photo.exifAperture {
                            Text("f/\(String(format: "%.1f", aperture))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let shutterSpeed = photo.exifShutterSpeed {
                            Text(shutterSpeed)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let iso = photo.exifIso {
                            Text("ISO\(iso)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let focalLength = photo.exifFocalLength {
                            Text("\(Int(focalLength))mm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Rating and Color Tag
                HStack(spacing: 6) {
                    if rating > 0 {
                        RatingPickerLabel(rating: rating)
                    }
                    ColorTagIndicator(colorTag: colorTag, size: 10)
                }

                // User tags if available
                if let tags = photo.userTags, !tags.isEmpty {
                    Text(tags)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .help("Tags: \(tags)")
                }

                // User description if available
                if let description = photo.userDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                        .lineLimit(2)
                        .help(description)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: thumbnailSize, alignment: .leading)
        }
        .onAppear {
            rating = photo.rating
            colorTag = photo.colorTag
        }
        .onChange(of: photo.rating) { _, newValue in
            rating = newValue
        }
        .onChange(of: photo.colorTag) { _, newValue in
            colorTag = newValue
        }
    }
}

// MARK: - Contact sheet generation

enum ContactSheetError: LocalizedError {
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .cannotCreatePDF: return "Could not create the PDF file"
        }
    }
}

enum ContactSheetGenerator {
    /// Escapes text for HTML element content and attribute values.
    static func escapeHTML(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Writes the contact sheet to a temporary file and returns it (a zip for HTML, a PDF otherwise).
    static func generate(photos: [PhotoFile], roots: [RootDirectory], options: ContactSheetOptions,
                         thumbnail: (PhotoFile) -> NSImage?) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        switch options.format {
        case .html:
            return try html(photos: photos, roots: roots, options: options, thumbnail: thumbnail, tempDir: tempDir, timestamp: timestamp)
        case .pdf:
            return try pdf(photos: photos, roots: roots, options: options, thumbnail: thumbnail, tempDir: tempDir, timestamp: timestamp)
        }
    }

    private static func html(photos: [PhotoFile], roots: [RootDirectory], options: ContactSheetOptions,
                             thumbnail: (PhotoFile) -> NSImage?, tempDir: URL, timestamp: Int) throws -> URL {
        let e = escapeHTML
        let exportDir = tempDir.appendingPathComponent("ContactSheet_\(timestamp)")
        let imagesDir = exportDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var html = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Contact Sheet</title><style>body{font-family:system-ui;margin:20px;background:#f5f5f5}h1{text-align:center}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:20px}.card{background:white;border-radius:8px;padding:15px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}.card img{width:100%;height:300px;object-fit:cover;border-radius:4px}.info{margin-top:10px;font-size:0.85em;color:#333;line-height:1.5}.filename{font-weight:bold;font-size:1.1em;margin-bottom:8px}.path{font-size:0.8em;color:#666;font-family:monospace;word-break:break-all;margin:6px 0}.description{font-style:italic;color:#555;margin:8px 0;padding:8px;background:#f9f9f9;border-radius:4px}.date{color:#007aff;font-weight:500}</style></head><body><h1>Contact Sheet</h1><p style="text-align:center">\(photos.count) photos - Generated \(e(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)))</p><div class="grid">
"""

        for (index, photo) in photos.enumerated() {
            guard let image = thumbnail(photo),
                  let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else { continue }
            let imageName = "photo_\(index).jpg"
            try? jpegData.write(to: imagesDir.appendingPathComponent(imageName))

            var fullPath = ""
            if let rootDir = roots.first(where: { $0.id == photo.rootDirectoryId }) {
                fullPath = (rootDir.path as NSString).appendingPathComponent(photo.relativePath)
            }

            html += "<div class=\"card\"><img src=\"images/\(imageName)\" alt=\"\(e(photo.fileName))\"><div class=\"info\">"

            if options.includeFilePath && !fullPath.isEmpty {
                html += "<div class=\"path\">📁 \(e(fullPath))</div>"
            }
            if options.includeFileName {
                html += "<div class=\"filename\">\(e(photo.fileName))</div>"
            }
            if options.includeDate, let dateTaken = photo.exifDateTaken {
                let dateStr = DateFormatter.localizedString(from: dateTaken, dateStyle: .medium, timeStyle: .short)
                html += "<div class=\"date\">📅 \(e(dateStr))</div>"
            }

            var techInfo = ""
            if options.includeDimensions, let width = photo.imageWidth, let height = photo.imageHeight {
                techInfo += "📐 \(width) × \(height)"
            }
            if options.includeFileSize {
                let sizeInMB = Double(photo.fileSize) / (1024 * 1024)
                if !techInfo.isEmpty { techInfo += " " }
                techInfo += String(format: "%.1fMB", sizeInMB)
            }
            if !techInfo.isEmpty {
                html += "<div>\(techInfo)</div>"
            }

            if options.includeCamera, let camera = photo.exifCameraModel {
                html += "<div>📷 \(e(camera))</div>"
            }
            if options.includeLens, let lens = photo.exifLensModel {
                html += "<div>\(e(lens))</div>"
            }
            if options.includeExposure {
                let exposure = exposureText(photo)
                if !exposure.isEmpty {
                    html += "<div>\(e(exposure))</div>"
                }
            }
            if options.includeDescription, let desc = photo.userDescription, !desc.isEmpty {
                html += "<div class=\"description\">\(e(desc))</div>"
            }
            if options.includeTags, let tags = photo.userTags, !tags.isEmpty {
                html += "<div>🏷️ \(e(tags))</div>"
            }
            html += "</div></div>"
        }

        html += "</div></body></html>"
        try html.write(to: exportDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("ContactSheet_\(timestamp).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", exportDir.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        return zipURL
    }

    private static func exposureText(_ photo: PhotoFile) -> String {
        var parts: [String] = []
        if let aperture = photo.exifAperture { parts.append(String(format: "f/%.1f", aperture)) }
        if let shutter = photo.exifShutterSpeed { parts.append(shutter) }
        if let iso = photo.exifIso { parts.append("ISO\(iso)") }
        if let focal = photo.exifFocalLength { parts.append("\(Int(focal))mm") }
        return parts.joined(separator: " ")
    }

    private static func pdf(photos: [PhotoFile], roots: [RootDirectory], options: ContactSheetOptions,
                            thumbnail: (PhotoFile) -> NSImage?, tempDir: URL, timestamp: Int) throws -> URL {
        let pdfURL = tempDir.appendingPathComponent("ContactSheet_\(timestamp).pdf")
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 40
        let columns = 3
        let spacing: CGFloat = 15
        let contentWidth = pageSize.width - (margin * 2)
        let thumbWidth = (contentWidth - (spacing * CGFloat(columns - 1))) / CGFloat(columns)
        let thumbHeight = thumbWidth * 0.75
        let cellHeight = thumbHeight + 140
        
        guard let pdfContext = CGContext(pdfURL as CFURL, mediaBox: nil, nil) else {
            throw ContactSheetError.cannotCreatePDF
        }
        
        var yPosition = pageSize.height - margin
        var column = 0
        
        // Title page
        pdfContext.beginPDFPage(nil)
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.black]
        let title = "Contact Sheet" as NSString
        title.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 30), withAttributes: titleAttrs)
        
        let subtitleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray]
        let subtitle = "\(photos.count) photos - Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))" as NSString
        subtitle.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 55), withAttributes: subtitleAttrs)
        
        yPosition = pageSize.height - margin - 100
        
        // Draw thumbnails
        for photo in photos {
            // Check if we need a new page
            if yPosition - cellHeight < margin {
                pdfContext.endPDFPage()
                pdfContext.beginPDFPage(nil)
                yPosition = pageSize.height - margin
                column = 0
            }
            
            let xPosition = margin + (CGFloat(column) * (thumbWidth + spacing))
            
            // Helper function to draw text in PDF using NSGraphicsContext
            func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
                pdfContext.saveGState()
                let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsContext
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                (text as NSString).draw(at: point, withAttributes: attrs)
                
                NSGraphicsContext.restoreGraphicsState()
                pdfContext.restoreGState()
            }
            
            var currentY = yPosition
            let regularFont = NSFont.systemFont(ofSize: 6.5)
            let boldFont = NSFont.boldSystemFont(ofSize: 8)
            let tinyFont = NSFont.systemFont(ofSize: 5.5)
            
            // Full file path at top (in smaller font)
            if options.includeFilePath, let rootDir = roots.first(where: { $0.id == photo.rootDirectoryId }) {
                let fullPath = (rootDir.path as NSString).appendingPathComponent(photo.relativePath)
                // Split path into multiple lines if too long
                if fullPath.count > 50 {
                    let parts = fullPath.split(separator: "/").map(String.init)
                    var pathLine = "/"
                    for part in parts {
                        if (pathLine + part).count > 50 {
                            drawText(pathLine, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                            currentY -= 7
                            pathLine = "/" + part + "/"
                        } else {
                            pathLine += part + "/"
                        }
                    }
                    if !pathLine.isEmpty && pathLine != "/" {
                        drawText(pathLine, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                        currentY -= 7
                    }
                } else {
                    drawText(fullPath, at: CGPoint(x: xPosition, y: currentY), font: tinyFont, color: .darkGray)
                    currentY -= 7
                }
                currentY -= 2 // Extra spacing after path
            }
            
            // Filename
            if options.includeFileName {
                drawText(photo.fileName, at: CGPoint(x: xPosition, y: currentY), font: boldFont, color: .black)
                currentY -= 9
            }
            
            // Date and time
            if options.includeDate, let dateTaken = photo.exifDateTaken {
                let dateStr = DateFormatter.localizedString(from: dateTaken, dateStyle: .short, timeStyle: .short)
                drawText(dateStr, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                currentY -= 8
            }
            
            // Dimensions and file size
            var techInfo = ""
            if options.includeDimensions, let width = photo.imageWidth, let height = photo.imageHeight {
                techInfo = "\(width)×\(height)"
            }
            if options.includeFileSize {
                let sizeInMB = Double(photo.fileSize) / (1024 * 1024)
                if !techInfo.isEmpty { techInfo += " " }
                techInfo += String(format: "%.1fMB", sizeInMB)
            }
            if !techInfo.isEmpty {
                drawText(techInfo, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                currentY -= 8
            }
            
            // Camera and lens
            if options.includeCamera, let camera = photo.exifCameraModel {
                drawText(camera, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .darkGray)
                currentY -= 8
            }
            if options.includeLens, let lens = photo.exifLensModel {
                drawText(lens, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .darkGray)
                currentY -= 8
            }
            
            // Exposure settings
            if options.includeExposure {
                var exposureInfo = ""
                if let aperture = photo.exifAperture {
                    exposureInfo = String(format: "f/%.1f", aperture)
                }
                if let shutter = photo.exifShutterSpeed {
                    if !exposureInfo.isEmpty { exposureInfo += " " }
                    exposureInfo += shutter
                }
                if let iso = photo.exifIso {
                    if !exposureInfo.isEmpty { exposureInfo += " " }
                    exposureInfo += "ISO\(iso)"
                }
                if let focal = photo.exifFocalLength {
                    if !exposureInfo.isEmpty { exposureInfo += " " }
                    exposureInfo += "\(Int(focal))mm"
                }
                if !exposureInfo.isEmpty {
                    drawText(exposureInfo, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                    currentY -= 8
                }
            }
            
            // Draw thumbnail
            currentY -= 3
            let imageRect = CGRect(x: xPosition, y: currentY - thumbHeight, width: thumbWidth, height: thumbHeight)
            
            if let thumbnail = thumbnail(photo) {
                pdfContext.saveGState()
                let ctx = NSGraphicsContext(cgContext: pdfContext, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                thumbnail.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
                pdfContext.restoreGState()
            } else {
                pdfContext.setFillColor(NSColor.lightGray.cgColor)
                pdfContext.fill(imageRect)
            }
            
            // Border
            pdfContext.setStrokeColor(NSColor.gray.cgColor)
            pdfContext.setLineWidth(0.5)
            pdfContext.stroke(imageRect)
            
            currentY = imageRect.minY - 3
            
            // Description below image
            if options.includeDescription, let desc = photo.userDescription, !desc.isEmpty {
                let descText = desc.count > 45 ? String(desc.prefix(45)) + "..." : desc
                drawText(descText, at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                currentY -= 9
            }
            
            // Tags
            if options.includeTags, let tags = photo.userTags, !tags.isEmpty {
                drawText("🏷️ \(tags)", at: CGPoint(x: xPosition, y: currentY), font: regularFont, color: .black)
                currentY -= 9
            }
            
            column += 1
            if column >= columns {
                column = 0
                yPosition -= cellHeight + spacing
            }
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        return pdfURL
    }
}
