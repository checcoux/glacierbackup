import SwiftUI

@main
struct GlacierBackupApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Glacier Backup", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 560, minHeight: 360)
        }
        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
