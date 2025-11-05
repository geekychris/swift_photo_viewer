import SwiftUI
//foo
struct SettingsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var showingResetAlert = false
    
    var body: some View {
        Form {
            Section("Database") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database Location")
                        .font(.headline)
                    
                    Text("~/Library/Application Support/PhotoManager/PhotoManager.sqlite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Reset Database") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thumbnails")
                        .font(.headline)
                    
                    Text("~/Library/Application Support/PhotoManager/Thumbnails/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Clean Orphaned Thumbnails") {
                        // TODO: Implement cleanup
                    }
                }
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PhotoManager")
                        .font(.headline)
                    
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("A photo management application for organizing and browsing your photo collections.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
        .alert("Reset Database", isPresented: $showingResetAlert) {
            Button("Reset", role: .destructive) {
                // TODO: Implement database reset
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all scanned photo data and thumbnails. Your actual photo files will not be affected. This action cannot be undone.")
        }
    }
}
