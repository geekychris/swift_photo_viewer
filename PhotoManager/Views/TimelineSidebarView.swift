import SwiftUI
//foo
struct TimelineSidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var yearGroups: [(String, [(String, [PhotoFile])])] = []
    @State private var expandedYears: Set<String> = []
    @State private var selectedYearMonth: String?
    
    var body: some View {
        List(selection: $selectedYearMonth) {
            ForEach(yearGroups, id: \.0) { year, monthGroups in
                Section {
                    if expandedYears.contains(year) {
                        ForEach(monthGroups, id: \.0) { month, photos in
                            TimelineMonthRowView(
                                yearMonth: month,
                                photos: photos,
                                isSelected: selectedYearMonth == month
                            )
                            .tag(month)
                        }
                    }
                } header: {
                    TimelineYearHeaderView(
                        year: year,
                        totalPhotos: monthGroups.reduce(0) { $0 + $1.1.count },
                        isExpanded: expandedYears.contains(year),
                        onToggle: {
                            toggleYearExpansion(year)
                        }
                    )
                }
            }
        }
        .listStyle(SidebarListStyle())
        .onAppear {
            loadTimelineData()
        }
        .onChange(of: photoLibrary.rootDirectories) {
            loadTimelineData()
        }
    }
    
    private func loadTimelineData() {
        yearGroups = photoLibrary.getPhotosGroupedByYear()
        
        // Expand the most recent year by default
        if let firstYear = yearGroups.first?.0 {
            expandedYears.insert(firstYear)
        }
    }
    
    private func toggleYearExpansion(_ year: String) {
        if expandedYears.contains(year) {
            expandedYears.remove(year)
        } else {
            expandedYears.insert(year)
        }
    }
}

struct TimelineYearHeaderView: View {
    let year: String
    let totalPhotos: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(year)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(totalPhotos) photos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

struct TimelineMonthRowView: View {
    let yearMonth: String
    let photos: [PhotoFile]
    let isSelected: Bool
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        
        if let date = formatter.date(from: yearMonth) {
            formatter.dateFormat = "MMMM"
            return formatter.string(from: date)
        }
        
        return yearMonth
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .font(.caption)
                
                Text(monthName)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(photos.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show a few sample thumbnails
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(photos.prefix(5))) { photo in
                            TimelineThumbnailView(photo: photo)
                        }
                        
                        if photos.count > 5 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text("+\(photos.count - 5)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
}

struct TimelineThumbnailView: View {
    let photo: PhotoFile
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        Group {
            if let thumbnailImage = thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    )
            }
        }
        .frame(width: 40, height: 40)
        .clipped()
        .cornerRadius(4)
        .onAppear {
            thumbnailImage = photoLibrary.getThumbnailImage(for: photo)
        }
    }
}
