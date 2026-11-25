import SwiftUI
import Foundation

@main
struct PhotoManagerApp: App {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var photoLibrary = PhotoLibrary()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseManager)
                .environmentObject(photoLibrary)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            DebugCommands()
        }
        
        Settings {
            SettingsView()
                .environmentObject(databaseManager)
        }
        
        Window("Organise Library", id: "organise") {
            OrganizeWorkbenchView()
                .environmentObject(photoLibrary)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 900)
        
        Window("Library Insights", id: "insights") {
            LibraryInsightsView()
                .environmentObject(photoLibrary)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        
        WindowGroup("Database Debug", id: "database-debug") {
            DatabaseDebugView()
                .environmentObject(databaseManager)
        }
        .defaultPosition(.center)
        .defaultSize(width: 1000, height: 700)
    }
}

struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandMenu("Library") {
            Button("Organise Library…") { openWindow(id: "organise") }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Library Insights") { openWindow(id: "insights") }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandGroup(after: .appInfo) {
            Button("Database Debug Window") {
                openWindow(id: "database-debug")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
