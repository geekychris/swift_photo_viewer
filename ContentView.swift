import SwiftUI

struct ContentView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var selectedTab = 0
    @State private var showingDirectoryPicker = false
    @State private var selectedPhoto: PhotoFile?
    @State private var selectedDirectoryId: Int64?
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
    @State private var sidebarWidth: CGFloat = 500
    
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
                                    DatePicker("", selection: Binding(
                                        get: { startDate ?? Date.distantPast },
                                        set: { startDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .onChange(of: startDate) { _, _ in updateSearchState() }
                                    
                                    Text("to")
                                        .font(.caption2)
                                    
                                    DatePicker("", selection: Binding(
                                        get: { endDate ?? Date() },
                                        set: { endDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .onChange(of: endDate) { _, _ in updateSearchState() }
                                }
                                
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
                        DirectorySidebarView(selectedDirectoryId: $selectedDirectoryId, sidebarWidth: $sidebarWidth)
                    case 1:
                        TimelineSidebarView(sidebarWidth: $sidebarWidth)
                    case 2:
                        DuplicatesSidebarView(sidebarWidth: $sidebarWidth)
                    default:
                        DirectorySidebarView(selectedDirectoryId: $selectedDirectoryId, sidebarWidth: $sidebarWidth)
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
        startDate != nil || endDate != nil || !selectedCamera.isEmpty ||
        minAperture != nil || maxAperture != nil || minISO != nil || maxISO != nil
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
        updateSearchState()
    }
}
