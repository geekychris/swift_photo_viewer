import SwiftUI
//foo
struct DuplicatesSidebarView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var expandedGroups: Set<String> = []
    @State private var viewMode: DuplicateViewMode = .byFile
    @State private var showingExportSuccess = false
    @State private var exportedFileURL: URL?
    
    enum DuplicateViewMode: String, CaseIterable {
        case byFile = "By File"
        case byDirectory = "By Directory"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented control and export button
            HStack {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(DuplicateViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Spacer()
                
                Button {
                    exportToCSV()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV")
                    }
                }
                .buttonStyle(.borderless)
                .help("Export duplicates to CSV file")
            }
            .frame(maxWidth: .infinity)
            .padding()
            
            Divider()
            
            // Content based on view mode
            if viewMode == .byFile {
                DuplicatesByFileView(sidebarWidth: $sidebarWidth, selectedPhoto: $selectedPhoto)
            } else {
                DuplicatesByDirectoryView(sidebarWidth: $sidebarWidth, selectedPhoto: $selectedPhoto)
            }
        }
        .alert("CSV Exported", isPresented: $showingExportSuccess) {
            Button("Open in Finder") {
                if let url = exportedFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let url = exportedFileURL {
                Text("Duplicates exported to:\n\(url.path)")
            }
        }
    }
    
    private func exportToCSV() {
        if let url = photoLibrary.exportDuplicatesToCSV(includeDirectoryView: viewMode == .byDirectory) {
            exportedFileURL = url
            showingExportSuccess = true
        }
    }
    
    private func toggleExpansion(for group: DuplicateGroup) {
        if expandedGroups.contains(group.fileHash) {
            expandedGroups.remove(group.fileHash)
        } else {
            expandedGroups.insert(group.fileHash)
        }
    }
}

// Extracted the original file-based view
struct DuplicatesByFileView: View {
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var sidebarWidth: CGFloat
    @Binding var selectedPhoto: PhotoFile?
    @State private var expandedGroups: Set<String> = []
    
    var body: some View {
        ScrollView {
                LazyVStack(spacing: 0) {
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
                            selectedPhoto: $selectedPhoto,
                            onToggleExpanded: {
                                toggleExpansion(for: group)
                            }
                        )
                        
                        Divider()
                    }
                    }
                }
                .frame(width: sidebarWidth - 20)
                .padding(.horizontal, 10)
        }
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
    @Binding var selectedPhoto: PhotoFile?
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
                    
                    // Show thumbnail of first file with hover and click
                    if let firstFile = group.files.first {
                        ReusableHoverThumbnail(photo: firstFile, size: 40, onTap: {
                            selectedPhoto = firstFile
                        })
                        .environmentObject(photoLibrary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(group.files) { file in
                        DuplicateFileRowView(file: file, selectedPhoto: $selectedPhoto)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct DuplicateFileRowView: View {
    let file: PhotoFile
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail with hover preview and click
            ReusableHoverThumbnail(photo: file, size: 32, onTap: {
                selectedPhoto = file
            })
            .environmentObject(photoLibrary)
            
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
        .alert("Move Photo to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                photoLibrary.movePhotoToTrash(file)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to move '\(file.fileName)' to the Trash?\n\nThis will move the file to the Trash and remove it from the database.")
        }
    }
}
