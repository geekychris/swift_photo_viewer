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
        
        Settings {
            SettingsView()
                .environmentObject(databaseManager)
        }
    }
}
