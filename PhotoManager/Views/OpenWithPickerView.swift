import SwiftUI
import AppKit

struct OpenWithPickerView: View {
    let photoPath: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @AppStorage("preferredImageEditor") private var preferredEditorPath: String = ""
    @State private var availableApps: [AppInfo] = []
    @State private var isLoading = true
    @State private var securityScopedURL: URL?
    @State private var isAccessingSecurityScope = false
    
    struct AppInfo: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let icon: NSImage?
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Open With")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            if isLoading {
                ProgressView("Finding compatible applications...")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No compatible applications found")
                        .foregroundColor(.secondary)
                    
                    Button("Select Manually...") {
                        selectManually()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Preferred app section
                        if !preferredEditorPath.isEmpty,
                           let preferredApp = availableApps.first(where: { $0.path == preferredEditorPath }) {
                            Text("Preferred")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.top)
                            
                            AppRowView(
                                app: preferredApp,
                                isPreferred: true,
                                onOpen: { openWith(app: preferredApp) },
                                onSetPreferred: nil
                            )
                            
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("Other Applications")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                        
                        ForEach(availableApps.filter { $0.path != preferredEditorPath }) { app in
                            AppRowView(
                                app: app,
                                isPreferred: false,
                                onOpen: { openWith(app: app) },
                                onSetPreferred: { setAsPreferred(app: app) }
                            )
                            
                            Divider()
                        }
                        
                        // Manual selection option
                        Button(action: selectManually) {
                            HStack {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title)
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Choose Application...")
                                        .fontWeight(.medium)
                                    Text("Browse for an application")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadAvailableApps()
            startAccessingSecurityScope()
        }
        .onDisappear {
            stopAccessingSecurityScope()
        }
    }
    
    private func startAccessingSecurityScope() {
        // Find the photo's root directory to get bookmark data
        let fileURL = URL(fileURLWithPath: photoPath)
        let parentPath = fileURL.deletingLastPathComponent().path
        
        // Try to find a root directory that matches
        for rootDir in photoLibrary.rootDirectories {
            if parentPath.hasPrefix(rootDir.path), let bookmarkData = rootDir.bookmarkData {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale)
                    
                    isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
                    securityScopedURL = url
                    print("🔓 Started security-scoped access for Open With: \(isAccessingSecurityScope)")
                    break
                } catch {
                    print("⚠️ Failed to resolve bookmark: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func stopAccessingSecurityScope() {
        if isAccessingSecurityScope {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            print("🔒 Stopped security-scoped access")
        }
    }
    
    private func loadAvailableApps() {
        Task {
            let fileURL = URL(fileURLWithPath: photoPath)
            
            // Get all applications that can open this file type
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            
            let appInfos = apps.compactMap { appURL -> AppInfo? in
                let name = appURL.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                return AppInfo(name: name, path: appURL.path, icon: icon)
            }
            
            await MainActor.run {
                self.availableApps = appInfos.sorted { $0.name < $1.name }
                self.isLoading = false
            }
        }
    }
    
    private func openWith(app: AppInfo) {
        let fileURL = URL(fileURLWithPath: photoPath)
        let appURL = URL(fileURLWithPath: app.path)
        
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        
        // Keep security access for a moment to allow the app to open
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            dismiss()
        }
    }
    
    private func setAsPreferred(app: AppInfo) {
        preferredEditorPath = app.path
    }
    
    private func selectManually() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.message = "Select an application to open the image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        
        panel.begin { [self] response in
            if response == .OK, let appURL = panel.url {
                let fileURL = URL(fileURLWithPath: photoPath)
                NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                
                // Keep security access for a moment to allow the app to open
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            }
        }
    }
}

struct AppRowView: View {
    let app: OpenWithPickerView.AppInfo
    let isPreferred: Bool
    let onOpen: () -> Void
    let onSetPreferred: (() -> Void)?
    
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "app")
                        .font(.title)
                        .frame(width: 40, height: 40)
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(app.name)
                            .fontWeight(.medium)
                        
                        if isPreferred {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Text(app.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !isPreferred, let setPreferred = onSetPreferred {
                    Button(action: setPreferred) {
                        Image(systemName: "star")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Set as preferred application")
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.gray.opacity(0.05)
                .opacity(isPreferred ? 1 : 0)
        )
    }
}
