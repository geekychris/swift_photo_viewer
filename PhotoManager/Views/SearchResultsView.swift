import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "search")

struct SearchResultsView: View {
    let searchText: String
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var searchResults: [PhotoFile] = []
    @State private var thumbnailSize: CGFloat = 200
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 16)]
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
    }
    
    private func performSearch() {
        logger.info("Performing search for: \(searchText, privacy: .public)")
        searchResults = photoLibrary.searchPhotos(query: searchText)
        logger.info("Found \(searchResults.count, privacy: .public) results")
    }
}
