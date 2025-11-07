import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "search")

struct SearchResultsView: View {
    let searchText: String
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var searchResults: [PhotoFile] = []
    @State private var thumbnailSize: CGFloat = 200
    @State private var minRating: Int = 0
    @State private var selectedColors: Set<String> = []
    @State private var showFilters: Bool = false
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
    }
    
    private var availableColors: [(id: String, name: String, color: Color)] {
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
    
    private var filterCount: Int {
        (minRating > 0 ? 1 : 0) + selectedColors.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack {
                Text("Search Results: \"\(searchText)\"")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(searchResults.count) photos found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Filter controls
            VStack(spacing: 12) {
                HStack {
                    Button {
                        showFilters.toggle()
                    } label: {
                        HStack {
                            Image(systemName: showFilters ? "chevron.down" : "chevron.right")
                            Text("Filters")
                            if minRating > 0 || !selectedColors.isEmpty {
                                Text("(\(filterCount))")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    if minRating > 0 || !selectedColors.isEmpty {
                        Button("Clear Filters") {
                            minRating = 0
                            selectedColors.removeAll()
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                if showFilters {
                    VStack(alignment: .leading, spacing: 12) {
                        // Rating filter
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minimum Rating")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 4) {
                                ForEach(0...5, id: \.self) { index in
                                    Button {
                                        minRating = index
                                    } label: {
                                        Image(systemName: index > 0 && index <= minRating ? "flag.fill" : "flag")
                                            .foregroundColor(index > 0 && index <= minRating ? .orange : .gray.opacity(0.4))
                                    }
                                    .buttonStyle(.plain)
                                    .help("At least \(index) flag\(index == 1 ? "" : "s")")
                                }
                            }
                        }
                        
                        // Color filter
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Colors")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 8) {
                                ForEach(availableColors, id: \.id) { colorOption in
                                    Button {
                                        if selectedColors.contains(colorOption.id) {
                                            selectedColors.remove(colorOption.id)
                                        } else {
                                            selectedColors.insert(colorOption.id)
                                        }
                                    } label: {
                                        Circle()
                                            .fill(colorOption.color)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                                            )
                                            .overlay(
                                                selectedColors.contains(colorOption.id) ?
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                                : nil
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(colorOption.name)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            
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
            if searchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    
                    Text("No photos found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Try searching for different keywords")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(searchResults) { photo in
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
        .onAppear {
            performSearch()
        }
        .onChange(of: searchText) {
            performSearch()
        }
        .onChange(of: minRating) {
            performSearch()
        }
        .onChange(of: selectedColors) {
            performSearch()
        }
    }
    
    private func performSearch() {
        logger.info("Performing search - query: \(searchText, privacy: .public), minRating: \(minRating, privacy: .public), colors: \(selectedColors.count, privacy: .public)")
        
        // Get all results matching text search and rating
        let ratingFilter = minRating > 0 ? minRating : nil
        var results = photoLibrary.searchPhotos(query: searchText, minRating: ratingFilter, colorTag: nil)
        
        // Apply color filter if colors are selected
        if !selectedColors.isEmpty {
            results = results.filter { photo in
                guard let colorTag = photo.colorTag else { return false }
                return selectedColors.contains(colorTag)
            }
        }
        
        searchResults = results
        logger.info("Found \(searchResults.count, privacy: .public) results")
    }
}
