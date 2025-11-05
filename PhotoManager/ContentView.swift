import SwiftUI
//foo
struct ContentView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var selectedTab = 0
    @State private var showingDirectoryPicker = false
    @State private var selectedPhoto: PhotoFile?
    @State private var selectedDirectoryId: Int64?
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var showingFilters = false
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?
    @State private var filterCamera = ""
    @State private var filterMinAperture: Double?
    @State private var filterMaxAperture: Double?
    @State private var filterMinISO: Int?
    @State private var filterMaxISO: Int?
    
    var body: some View {
        NavigationSplitView {
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
                
                // SEARCH BAR - BRIGHT AND VISIBLE
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                        
                        TextField("Search photos...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: searchText) {
                                updateSearchState()
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                clearAllFilters()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button {
                            showingFilters.toggle()
                        } label: {
                            Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 18))
                                .foregroundColor(hasActiveFilters ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Advanced Filters")
                    }
                    
                    // Filter panel
                    if showingFilters {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Advanced Filters")
                                .font(.caption)
                                .fontWeight(.bold)
                            
                            // Date range
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date Range")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    DatePicker("From", selection: Binding(
                                        get: { filterStartDate ?? Date.distantPast },
                                        set: { filterStartDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .font(.caption)
                                    .onChange(of: filterStartDate) { _, _ in updateSearchState() }
                                    
                                    Text("to")
                                        .font(.caption2)
                                    
                                    DatePicker("To", selection: Binding(
                                        get: { filterEndDate ?? Date() },
                                        set: { filterEndDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .font(.caption)
                                    .onChange(of: filterEndDate) { _, _ in updateSearchState() }
                                }
                            }
                            
                            Divider()
                            
                            // Camera
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Camera Model")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                TextField("e.g., Canon, Sony...", text: $filterCamera)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onChange(of: filterCamera) { _, _ in updateSearchState() }
                            }
                            
                            Divider()
                            
                            // Aperture
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Aperture (f-stop)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        TextField("Min", value: $filterMinAperture, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption)
                                            .frame(width: 50)
                                            .onChange(of: filterMinAperture) { _, _ in updateSearchState() }
                                        
                                        Text("-")
                                        
                                        TextField("Max", value: $filterMaxAperture, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption)
                                            .frame(width: 50)
                                            .onChange(of: filterMaxAperture) { _, _ in updateSearchState() }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // ISO
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ISO")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    TextField("Min", value: $filterMinISO, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 50)
                                        .onChange(of: filterMinISO) { _, _ in updateSearchState() }
                                    
                                    Text("-")
                                    
                                    TextField("Max", value: $filterMaxISO, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 50)
                                        .onChange(of: filterMaxISO) { _, _ in updateSearchState() }
                                }
                            }
                            
                            if hasActiveFilters {
                                HStack {
                                    Spacer()
                                    Button("Clear Filters") {
                                        clearFilterValues()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                )
                .padding(.horizontal)
                
                Divider()
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        DirectorySidebarView(selectedDirectoryId: $selectedDirectoryId)
                    case 1:
                        TimelineSidebarView()
                    case 2:
                        DuplicatesSidebarView()
                    default:
                        DirectorySidebarView(selectedDirectoryId: $selectedDirectoryId)
                    }
                }
                
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
            .frame(minWidth: 300, maxWidth: 400)
        } detail: {
            // Main content area
            if showingSearch {
                SimpleSearchView(
                    searchText: searchText,
                    startDate: filterStartDate,
                    endDate: filterEndDate,
                    camera: filterCamera,
                    minAperture: filterMinAperture,
                    maxAperture: filterMaxAperture,
                    minISO: filterMinISO,
                    maxISO: filterMaxISO,
                    selectedPhoto: $selectedPhoto
                )
            } else {
                PhotoGridView(selectedPhoto: $selectedPhoto, filterDirectoryId: selectedDirectoryId)
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
        filterStartDate != nil || filterEndDate != nil || !filterCamera.isEmpty ||
        filterMinAperture != nil || filterMaxAperture != nil ||
        filterMinISO != nil || filterMaxISO != nil
    }
    
    private func updateSearchState() {
        showingSearch = !searchText.isEmpty || hasActiveFilters
    }
    
    private func clearAllFilters() {
        searchText = ""
        clearFilterValues()
        showingSearch = false
    }
    
    private func clearFilterValues() {
        filterStartDate = nil
        filterEndDate = nil
        filterCamera = ""
        filterMinAperture = nil
        filterMaxAperture = nil
        filterMinISO = nil
        filterMaxISO = nil
        updateSearchState()
    }
}

// Simple inline search view with filters
struct SimpleSearchView: View {
    let searchText: String
    let startDate: Date?
    let endDate: Date?
    let camera: String
    let minAperture: Double?
    let maxAperture: Double?
    let minISO: Int?
    let maxISO: Int?
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var results: [PhotoFile] = []
    
    var body: some View {
        VStack {
            Text("Search Results: \(results.count) photos")
                .font(.headline)
                .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(results) { photo in
                        PhotoThumbnailView(
                            photo: photo,
                            thumbnailSize: 200,
                            onTap: { selectedPhoto = photo }
                        )
                    }
                }
                .padding()
            }
        }
        .onAppear {
            performSearch()
        }
        .onChange(of: searchText) { _, _ in
            performSearch()
        }
        .onChange(of: startDate) { _, _ in
            performSearch()
        }
        .onChange(of: endDate) { _, _ in
            performSearch()
        }
        .onChange(of: camera) { _, _ in
            performSearch()
        }
        .onChange(of: minAperture) { _, _ in
            performSearch()
        }
        .onChange(of: maxAperture) { _, _ in
            performSearch()
        }
        .onChange(of: minISO) { _, _ in
            performSearch()
        }
        .onChange(of: maxISO) { _, _ in
            performSearch()
        }
    }
    
    private func performSearch() {
        // Start with text search or all photos
        var filtered: [PhotoFile] = []
        
        if !searchText.isEmpty {
            filtered = photoLibrary.searchPhotos(query: searchText)
        } else {
            // Get all photos
            for directory in photoLibrary.rootDirectories {
                if let id = directory.id {
                    filtered.append(contentsOf: photoLibrary.getPhotosForDirectory(id))
                }
            }
        }
        
        // Apply date filters
        if let start = startDate {
            filtered = filtered.filter { ($0.exifDateTaken ?? $0.createdAt) >= start }
        }
        if let end = endDate {
            filtered = filtered.filter { ($0.exifDateTaken ?? $0.createdAt) <= end }
        }
        
        // Apply camera filter
        if !camera.isEmpty {
            filtered = filtered.filter { photo in
                photo.exifCameraModel?.localizedCaseInsensitiveContains(camera) ?? false
            }
        }
        
        // Apply aperture filters
        if let minAp = minAperture {
            filtered = filtered.filter { ($0.exifAperture ?? 0) >= minAp }
        }
        if let maxAp = maxAperture {
            filtered = filtered.filter { ($0.exifAperture ?? 999) <= maxAp }
        }
        
        // Apply ISO filters
        if let minIso = minISO {
            filtered = filtered.filter { ($0.exifIso ?? 0) >= minIso }
        }
        if let maxIso = maxISO {
            filtered = filtered.filter { ($0.exifIso ?? 999999) <= maxIso }
        }
        
        // Sort by date
        results = filtered.sorted { photo1, photo2 in
            let date1 = photo1.exifDateTaken ?? photo1.createdAt
            let date2 = photo2.exifDateTaken ?? photo2.createdAt
            return date1 > date2
        }
    }
}
