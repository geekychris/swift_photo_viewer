import SwiftUI
//foo
struct DuplicatesSidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var expandedGroups: Set<String> = []
    
    var body: some View {
        List {
            if photoLibrary.duplicateGroups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("No Duplicates Found")
                        .font(.headline)
                    
                    Text("All your photos appear to be unique!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(photoLibrary.duplicateGroups, id: \.fileHash) { group in
                    DuplicateGroupRowView(
                        group: group,
                        isExpanded: expandedGroups.contains(group.fileHash),
                        onToggleExpanded: {
                            toggleExpansion(for: group)
                        }
                    )
                }
            }
        }
        .listStyle(SidebarListStyle())
        .navigationTitle("\(photoLibrary.duplicateGroups.count) Duplicate Groups")
    }
    
    private func toggleExpansion(for group: DuplicateGroup) {
        if expandedGroups.contains(group.fileHash) {
            expandedGroups.remove(group.fileHash)
        } else {
            expandedGroups.insert(group.fileHash)
        }
    }
}

struct DuplicateGroupRowView: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    private var wastedSpace: String {
        let bytes = group.totalSize - (group.files.first?.fileSize ?? 0)
        return ByteCountFormatter().string(fromByteCount: bytes)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggleExpanded()
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(.orange)
                            
                            Text("\(group.duplicateCount) copies")
                                .fontWeight(.medium)
                        }
                        
                        Text("Wasting \(wastedSpace)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let firstFile = group.files.first {
                            Text(firstFile.fileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Show thumbnail of first file
                    if let firstFile = group.files.first,
                       let thumbnailImage = photoLibrary.getThumbnailImage(for: firstFile) {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipped()
                            .cornerRadius(6)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(group.files) { file in
                        DuplicateFileRowView(file: file)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DuplicateFileRowView: View {
    let file: PhotoFile
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let thumbnailImage = photoLibrary.getThumbnailImage(for: file) {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipped()
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(file.relativePath)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(ByteCountFormatter().string(fromByteCount: file.fileSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let dateTaken = file.exifDateTaken {
                        Text(dateTaken, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete this duplicate")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
        )
        .alert("Delete Photo", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let photoId = file.id {
                    photoLibrary.deletePhoto(photoId)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this photo from the database? This will not delete the actual file from disk.")
        }
    }
}
