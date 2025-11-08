import SwiftUI

struct DestinationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @Binding var selectedDestination: Destination?
    
    let operationType: OperationType
    let photoCount: Int
    
    @State private var showingFilePicker = false
    @State private var selectedDirectory: PhotoDirectory?
    
    enum OperationType {
        case copy
        case move
        
        var title: String {
            switch self {
            case .copy: return "Copy"
            case .move: return "Move"
            }
        }
        
        var verb: String {
            switch self {
            case .copy: return "copy"
            case .move: return "move"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(operationType.title) \(photoCount) photo\(photoCount == 1 ? "" : "s")")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                Text("Select destination:")
                    .font(.headline)
                
                // Managed directories
                if !photoLibrary.rootDirectories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Managed Directories")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(photoLibrary.rootDirectories) { directory in
                            Button {
                                selectedDirectory = directory
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(directory.name)
                                            .fontWeight(.medium)
                                        
                                        Text(directory.path)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedDirectory?.id == directory.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(12)
                                .background(selectedDirectory?.id == directory.id ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                }
                
                // Other location
                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Location")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.green)
                            
                            Text("Choose a folder...")
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Spacer()
            
            // Action buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(operationType.title) {
                    if let directory = selectedDirectory {
                        selectedDestination = .managedDirectory(directory)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDirectory == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
    }
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedDestination = .unmanagedPath(url.path)
                dismiss()
            }
        case .failure(let error):
            print("Error selecting folder: \(error)")
        }
    }
}
