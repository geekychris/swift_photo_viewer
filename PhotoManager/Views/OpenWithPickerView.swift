import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.photomarger", category: "openwith")

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
        // Find the root directory containing the photo to get its bookmark
        let parentPath = URL(fileURLWithPath: photoPath).deletingLastPathComponent().path
        let root = photoLibrary.rootDirectories
            .filter { parentPath == $0.path || parentPath.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        guard let bookmarkData = root?.bookmarkData else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
            securityScopedURL = url
        } catch {
            logger.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func stopAccessingSecurityScope() {
        if isAccessingSecurityScope {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
    }
    
    private func loadAvailableApps() {
        let path = photoPath
        Task {
            // Launch Services lookups and icon loading can be slow; keep them off the main thread.
            let appInfos = await Task.detached(priority: .userInitiated) { () -> [AppInfo] in
                let apps = NSWorkspace.shared.urlsForApplications(toOpen: URL(fileURLWithPath: path))
                return apps.map { appURL in
                    AppInfo(name: appURL.deletingPathExtension().lastPathComponent,
                            path: appURL.path,
                            icon: NSWorkspace.shared.icon(forFile: appURL.path))
                }
            }.value
            availableApps = appInfos.sorted { $0.name < $1.name }
            isLoading = false
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
