import SwiftUI

@main
struct GlacierBackupApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Glacier Backup", id: "main") {
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
