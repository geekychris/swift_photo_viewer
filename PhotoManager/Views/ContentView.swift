import SwiftUI

struct ContentView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var selectedTab = 0
    @State private var showingDirectoryPicker = false
    @State private var selectedPhoto: PhotoFile?
    @State private var selectedDirectoryId: Int64?
    @State private var selectedSubdirectoryPath: String?
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var showingFilters = false
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var selectedCamera: String = ""
    @State private var minAperture: Double?
    @State private var maxAperture: Double?
    @State private var minISO: Int?
    @State private var maxISO: Int?
    @State private var minRating: Int = 0
    @State private var selectedColors: Set<String> = []
    @State private var selectedTimelinePeriod: String?
    @State private var sidebarWidth: CGFloat = 500
    
    private var colorOptions: [(id: String, name: String, color: Color)] {
        [
            ("red", "Red", .red),
            ("orange", "Orange", .orange),
            ("yellow", "Yellow", .yellow),
            ("green", "Green", .green),
            ("blue", "Blue", .blue),
            ("purple", "Purple", .purple),
            ("gray", "Gray", .gray)
        ]
    }
    
    var body: some View {
        ResizableSplitView(minSidebarWidth: 300, maxSidebarWidth: 2000, sidebarWidth: $sidebarWidth) {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Photo Manager")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button {
                        showingDirectoryPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                .padding()
                
                Divider()
                
                // View Selection
                Picker("View Mode", selection: $selectedTab) {
                    Label("Directories", systemImage: "folder").tag(0)
                    Label("Timeline", systemImage: "calendar").tag(1)
                    Label("Duplicates", systemImage: "doc.on.doc").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                Divider()
                
                // Search and filters section - HIGHLY VISIBLE
                VStack(spacing: 8) {
                    // Search bar - prominent with background
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                        
                        TextField("Search photos...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: searchText) {
                                print("🔍 Search text changed: \(searchText)")
                                updateSearchState()
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                clearSearch()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button {
                            print("🎛 Filter button tapped, showing: \(showingFilters)")
                            showingFilters.toggle()
                        } label: {
                            Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 18))
                                .foregroundColor(hasActiveFilters ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Advanced Filters")
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    
                    // Advanced filters panel
                    if showingFilters {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Filters")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Divider()
                            
                            // Date range
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date Range")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("From")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let start = startDate {
                                            DatePicker("", selection: Binding(
                                                get: { start },
                                                set: { startDate = $0 }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                        } else {
                                            Button("Select date") {
                                                startDate = Date()
                                                updateSearchState()
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("To")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let end = endDate {
                                            DatePicker("", selection: Binding(
                                                get: { end },
                                                set: { endDate = $0 }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                        } else {
                                            Button("Select date") {
                                                endDate = Date()
                                                updateSearchState()
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }
                                .onChange(of: startDate) { _, _ in updateSearchState() }
                                .onChange(of: endDate) { _, _ in updateSearchState() }
                                
                                if startDate != nil || endDate != nil {
                                    Button("Clear Dates") {
                                        startDate = nil
                                        endDate = nil
                                        updateSearchState()
                                    }
                                    .font(.caption2)
                                }
                            }
                            
                            Divider()
                            
                            // Camera filter
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Camera")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                TextField("Camera model...", text: $selectedCamera)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onChange(of: selectedCamera) { _, _ in updateSearchState() }
                            }
                            
                            Divider()
                            
                            // Aperture range
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Aperture (f-stop)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    TextField("Min", value: $minAperture, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 60)
                                        .onChange(of: minAperture) { _, _ in updateSearchState() }
                                    
                                    Text("-")
                                    
                                    TextField("Max", value: $maxAperture, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 60)
                                        .onChange(of: maxAperture) { _, _ in updateSearchState() }
                                }
                            }
                            
                            Divider()
                            
                            // ISO range
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ISO")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    TextField("Min", value: $minISO, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 60)
                                        .onChange(of: minISO) { _, _ in updateSearchState() }
                                    
                                    Text("-")
                                    
                                    TextField("Max", value: $maxISO, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 60)
                                        .onChange(of: maxISO) { _, _ in updateSearchState() }
                                }
                            }
                            
                            Divider()
                            
                            // Rating filter
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Minimum Rating")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 3) {
                                    ForEach(0...5, id: \.self) { index in
                                        Button {
                                            minRating = index
                                            updateSearchState()
                                        } label: {
                                            Image(systemName: index > 0 && index <= minRating ? "flag.fill" : "flag")
                                                .foregroundColor(index > 0 && index <= minRating ? .orange : .gray.opacity(0.4))
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .help("At least \(index) flag\(index == 1 ? "" : "s")")
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Color filter
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Colors")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 6) {
                                    ForEach(colorOptions, id: \.id) { option in
                                        Button {
                                            if selectedColors.contains(option.id) {
                                                selectedColors.remove(option.id)
                                            } else {
                                                selectedColors.insert(option.id)
                                            }
                                            updateSearchState()
                                        } label: {
                                            Circle()
                                                .fill(option.color)
                                                .frame(width: 16, height: 16)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                                                )
                                                .overlay(
                                                    selectedColors.contains(option.id) ?
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.white)
                                                    : nil
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            if hasActiveFilters {
                                Button("Clear All Filters") {
                                    clearAllFilters()
                                }
                                .font(.caption)
                                .padding(.top, 4)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
                
                Divider()
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        DirectorySidebarView(
                            selectedDirectoryId: $selectedDirectoryId,
                            selectedSubdirectoryPath: $selectedSubdirectoryPath,
                            sidebarWidth: $sidebarWidth,
                            selectedPhoto: $selectedPhoto
                        )
                    case 1:
                        TimelineSidebarView(
                            sidebarWidth: $sidebarWidth,
                            selectedPhoto: $selectedPhoto,
                            selectedPeriod: $selectedTimelinePeriod
                        )
                    case 2:
                        DuplicatesSidebarView(sidebarWidth: $sidebarWidth, selectedPhoto: $selectedPhoto)
                    default:
                        DirectorySidebarView(
                            selectedDirectoryId: $selectedDirectoryId,
                            selectedSubdirectoryPath: $selectedSubdirectoryPath,
                            sidebarWidth: $sidebarWidth,
                            selectedPhoto: $selectedPhoto
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
                
                // Status
                if photoLibrary.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning...")
                            .font(.caption)
                    }
                    .padding()
                }
                
                if let errorMessage = photoLibrary.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
            }
        } detail: {
            // Main content area
            if showingSearch {
                FilteredSearchView(
                    searchText: searchText,
                    startDate: startDate,
                    endDate: endDate,
                    camera: selectedCamera,
                    minAperture: minAperture,
                    maxAperture: maxAperture,
                    minISO: minISO,
                    maxISO: maxISO,
                    minRating: minRating,
                    selectedColors: selectedColors,
                    filterDirectoryId: selectedDirectoryId,
                    filterSubdirectoryPath: selectedSubdirectoryPath,
                    filterTimelinePeriod: selectedTimelinePeriod,
                    selectedPhoto: $selectedPhoto
                )
            } else {
                PhotoGridView(
                    selectedPhoto: $selectedPhoto,
                    filterDirectoryId: selectedDirectoryId,
                    filterSubdirectoryPath: selectedSubdirectoryPath
                )
            }
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result)
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }
    
    private func handleDirectorySelection(_ result: Result<[URL], Error>) {
        NSLog("📁 ContentView: handleDirectorySelection called")
        switch result {
        case .success(let urls):
            NSLog("✅ ContentView: Successfully got URLs: %ld items", urls.count)
            if let url = urls.first {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    photoLibrary.errorMessage = "Failed to access directory. Please try again."
                    NSLog("❌ ContentView: Failed to start accessing security-scoped resource")
                    return
                }
                
                // Store bookmark data for future access
                var bookmarkData: Data? = nil
                do {
                    bookmarkData = try url.bookmarkData(options: [.withSecurityScope],
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)
                    NSLog("✅ ContentView: Created security-scoped bookmark")
                } catch {
                    NSLog("⚠️ ContentView: Failed to create bookmark: %@", error.localizedDescription)
                }
                
                let path = url.path
                let name = url.lastPathComponent
                NSLog("📂 ContentView: Selected directory - Path: %@, Name: %@", path, name)
                photoLibrary.addRootDirectory(path: path, name: name, bookmarkData: bookmarkData)
                NSLog("📂 ContentView: Called photoLibrary.addRootDirectory")
                
                // Don't stop accessing - we need it for scanning
                // url.stopAccessingSecurityScopedResource()
            } else {
                NSLog("❌ ContentView: No URL in the success result")
            }
        case .failure(let error):
            let errorMsg = "Failed to select directory: \(error.localizedDescription)"
            NSLog("❌ ContentView: \(errorMsg)")
            photoLibrary.errorMessage = errorMsg
        }
    }
    
    private var hasActiveFilters: Bool {
        startDate != nil || endDate != nil || !selectedCamera.isEmpty ||
        minAperture != nil || maxAperture != nil || minISO != nil || maxISO != nil ||
        minRating > 0 || !selectedColors.isEmpty
    }
    
    private func updateSearchState() {
        showingSearch = !searchText.isEmpty || hasActiveFilters
    }
    
    private func clearSearch() {
        searchText = ""
        clearAllFilters()
        showingSearch = false
    }
    
    private func clearAllFilters() {
        startDate = nil
        endDate = nil
        selectedCamera = ""
        minAperture = nil
        maxAperture = nil
        minISO = nil
        maxISO = nil
        minRating = 0
        selectedColors.removeAll()
        updateSearchState()
    }
}
