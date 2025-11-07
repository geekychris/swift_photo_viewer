import SwiftUI

struct DuplicateDeletionConfirmationView: View {
    let filesToDelete: [PhotoFile]
    let otherLocations: [PhotoFile]  // The files in the other directory
    let directoryPath: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Binding var selectedPhoto: PhotoFile?
    @EnvironmentObject var photoLibrary: PhotoLibrary
    
    private var totalSize: Int64 {
        filesToDelete.reduce(0) { $0 + $1.fileSize }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Confirm Deletion")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 4) {
                        Text("You are about to move \(filesToDelete.count) duplicate files to the Trash")
                            .font(.body)
                        
                        Text("Total size: \(ByteCountFormatter().string(fromByteCount: totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Debug: \(filesToDelete.count) files to delete, \(otherLocations.count) other locations")
                            .font(.caption2)
                            .foregroundColor(filesToDelete.isEmpty ? .red : .secondary)
                    }
                }
                .padding(.top, 16)
                .onAppear {
                    print("DuplicateDeletionConfirmationView appeared")
                    print("  Files to delete: \(filesToDelete.count)")
                    print("  Other locations: \(otherLocations.count)")
                }
            
            Divider()
            
            // Files list in a table
            VStack(alignment: .leading, spacing: 8) {
                Text("Files to be deleted from:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(directoryPath)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                
                // Table header
                HStack {
                    Text("To Delete")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(width: 200, alignment: .leading)
                    
                    Text("Size")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(width: 80, alignment: .leading)
                    
                    Text("Hash")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(width: 120, alignment: .leading)
                    
                    Text("Duplicate Kept")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(minWidth: 200, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                
                ScrollView {
                    VStack(spacing: 2) {
                        if filesToDelete.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                
                                Text("No files to display")
                                    .font(.headline)
                                
                                Text("This might be a bug. The directory claims to have duplicates, but the file list is empty.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                        } else {
                            ForEach(Array(filesToDelete.enumerated()), id: \.element.id) { index, fileToDelete in
                                if index < otherLocations.count {
                                    DuplicateFileRowForDeletion(
                                        fileToDelete: fileToDelete,
                                        otherFile: otherLocations[index],
                                        selectedPhoto: $selectedPhoto
                                    )
                                    .environmentObject(photoLibrary)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 200, maxHeight: 400)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
            }
            
            Divider()
            
            // Warning message
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("These files will be moved to macOS Trash")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("You can restore them from Trash if needed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
            
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Move \(filesToDelete.count) Files to Trash") {
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.bottom, 16)
            }
            .padding()
        }
        .frame(width: 950, height: 700)
    }
}

struct DuplicateFileRowForDeletion: View {
    let fileToDelete: PhotoFile
    let otherFile: PhotoFile
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedPhoto: PhotoFile?
    
    private var otherDirectoryPath: String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == otherFile.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return (otherFile.relativePath as NSString).deletingLastPathComponent }
        let directoryPath = (otherFile.relativePath as NSString).deletingLastPathComponent
        return (rootPath as NSString).appendingPathComponent(directoryPath)
    }
    
    private var shortHash: String {
        String(fileToDelete.fileHash.prefix(12))
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // TO DELETE section
            HStack(spacing: 6) {
                // Thumbnail with hover - file to delete
                ReusableHoverThumbnail(photo: fileToDelete, size: 40, onTap: {
                    selectedPhoto = fileToDelete
                })
                .environmentObject(photoLibrary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileToDelete.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.red)
                    
                    Text(getDirectoryPath(for: fileToDelete))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 200, alignment: .leading)
            
            // Size
            Text(ByteCountFormatter().string(fromByteCount: fileToDelete.fileSize))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Hash (shortened)
            Text(shortHash)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            // DUPLICATE KEPT section
            HStack(spacing: 6) {
                // Thumbnail with hover - file to keep
                ReusableHoverThumbnail(photo: otherFile, size: 40, onTap: {
                    selectedPhoto = otherFile
                })
                .environmentObject(photoLibrary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(otherFile.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.green)
                    
                    Text(getDirectoryPath(for: otherFile))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 200, alignment: .leading)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.01))
        .cornerRadius(2)
    }
    
    private func getDirectoryPath(for photo: PhotoFile) -> String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId })
        guard let rootPath = rootDir?.path else { return (photo.relativePath as NSString).deletingLastPathComponent }
        let directoryPath = (photo.relativePath as NSString).deletingLastPathComponent
        return (rootPath as NSString).appendingPathComponent(directoryPath)
    }
}
