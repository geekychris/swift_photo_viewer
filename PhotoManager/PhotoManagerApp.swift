import SwiftUI
import Foundation
//foo
@main
struct PhotoManagerApp: App {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var photoLibrary = PhotoLibrary()
    
    init() {
        NSLog("🚀 PhotoManagerApp: Application starting up")
        NSLog("🚀 PhotoManagerApp: databaseManager = %@", String(describing: databaseManager))
        NSLog("🚀 PhotoManagerApp: photoLibrary = %@", String(describing: photoLibrary))
    }
    
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
        CommandGroup(after: .appInfo) {
            Button("Database Debug Window") {
                openWindow(id: "database-debug")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
