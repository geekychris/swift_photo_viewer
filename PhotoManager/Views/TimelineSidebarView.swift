import SwiftUI
//foo

enum TimelineGranularity: String, CaseIterable {
    case month = "Monthly"
    case week = "Weekly"
    case day = "Daily"
}

struct TimelineSidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @Binding var selectedPeriod: String?
    @State private var yearGroups: [(String, [(String, [PhotoFile])])] = []
    @State private var expandedYears: Set<String> = []
    @State private var granularity: TimelineGranularity = .month
    
    var body: some View {
        VStack(spacing: 0) {
            // Granularity picker
            Picker("View", selection: $granularity) {
                ForEach(TimelineGranularity.allCases, id: \.self) { gran in
                    Text(gran.rawValue).tag(gran)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                    LazyVStack(spacing: 0) {
                    ForEach(yearGroups, id: \.0) { year, periodGroups in
                        TimelineYearHeaderView(
                            year: year,
                            totalPhotos: periodGroups.reduce(0) { $0 + $1.1.count },
                            isExpanded: expandedYears.contains(year),
                            onToggle: {
                                toggleYearExpansion(year)
                            }
                        )
                        
                        Divider()
                        
                        if expandedYears.contains(year) {
                            ForEach(periodGroups, id: \.0) { period, photos in
                                TimelinePeriodRowView(
                                    period: period,
                                    photos: photos,
                                    granularity: granularity,
                                    isSelected: selectedPeriod == period,
                                    selectedPhoto: $selectedPhoto
                                )
                                .onTapGesture {
                                    selectedPeriod = period
                                }
                                
                                Divider()
                            }
                        }
                        }
                    }
                    .frame(width: sidebarWidth - 20)
                    .padding(.horizontal, 10)
            }
        }
        .onAppear {
            loadTimelineData()
        }
        .onChange(of: photoLibrary.rootDirectories) {
            loadTimelineData()
        }
        .onChange(of: granularity) {
            loadTimelineData()
        }
    }
    
    private func loadTimelineData() {
        switch granularity {
        case .month:
            yearGroups = photoLibrary.getPhotosGroupedByYear()
        case .week:
            yearGroups = photoLibrary.getPhotosGroupedByYearAndWeek()
        case .day:
            yearGroups = photoLibrary.getPhotosGroupedByYearAndDay()
        }
        
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

struct TimelinePeriodRowView: View {
    let period: String
    let photos: [PhotoFile]
    let granularity: TimelineGranularity
    let isSelected: Bool
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingAllPhotos = false
    
    private var displayName: String {
        let formatter = DateFormatter()
        
        switch granularity {
        case .month:
            formatter.dateFormat = "yyyy-MM"
            if let date = formatter.date(from: period) {
                formatter.dateFormat = "MMMM"
                return formatter.string(from: date)
            }
        case .week:
            // Format: "yyyy-Www" (e.g., "2024-W15")
            let parts = period.split(separator: "-")
            if parts.count == 2, let weekNum = parts[1].dropFirst().description as String? {
                return "Week \(weekNum)"
            }
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: period) {
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
        
        return period
    }
    
    private var icon: String {
        switch granularity {
        case .month: return "calendar"
        case .week: return "calendar.badge.clock"
        case .day: return "calendar.circle"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.caption)
                
                Text(displayName)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(photos.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Show thumbnails that fit the available width
            if !photos.isEmpty {
                GeometryReader { geometry in
                    let thumbnailSize: CGFloat = 50
                    let spacing: CGFloat = 4
                    let availableWidth = geometry.size.width - 20 // account for padding
                    let thumbnailsPerRow = Int(availableWidth / (thumbnailSize + spacing))
                    let maxThumbnails = max(1, thumbnailsPerRow)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(Array(photos.prefix(maxThumbnails))) { photo in
                                TimelineThumbnailView(photo: photo, size: thumbnailSize, onTap: {
                                    selectedPhoto = photo
                                })
                                .environmentObject(photoLibrary)
                            }
                            
                            if photos.count > maxThumbnails {
                                Button {
                                    showingAllPhotos = true
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: thumbnailSize, height: thumbnailSize)
                                        .overlay(
                                            VStack(spacing: 2) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                Text("\(photos.count - maxThumbnails)")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .frame(height: 54)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .sheet(isPresented: $showingAllPhotos) {
            TimelinePhotoGridSheet(period: displayName, photos: photos)
                .presentationSizing(.fitted)
        }
    }
}

struct TimelineThumbnailView: View {
    let photo: PhotoFile
    let size: CGFloat
    var onTap: (() -> Void)? = nil
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    var body: some View {
        ReusableHoverThumbnail(photo: photo, size: size, onTap: onTap)
            .environmentObject(photoLibrary)
    }
}

struct TimelinePhotoGridSheet: View {
    let period: String
    let photos: [PhotoFile]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var selectedPhoto: PhotoFile?
    @State private var thumbnailSize: CGFloat = 150
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 100), spacing: 8)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(period)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("\(photos.count) photos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Thumbnail size control
            HStack {
                Text("Thumbnail Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $thumbnailSize, in: 80...300, step: 20)
                    .frame(width: 200)
                
                Text("\(Int(thumbnailSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(photos) { photo in
                        TimelineGridThumbnailView(photo: photo, thumbnailSize: thumbnailSize)
                            .onTapGesture {
                                selectedPhoto = photo
                            }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, idealWidth: 900, maxWidth: .infinity,
               minHeight: 400, idealHeight: 700, maxHeight: .infinity)
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }
}

struct TimelineGridThumbnailView: View {
    let photo: PhotoFile
    let thumbnailSize: CGFloat
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnailImage = thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipped()
            .cornerRadius(6)
            
            Text(photo.fileName)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: thumbnailSize)
        }
        .onAppear {
            thumbnailImage = photoLibrary.getThumbnailImage(for: photo)
        }
    }
}
