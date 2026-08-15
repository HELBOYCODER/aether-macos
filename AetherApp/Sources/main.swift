import SwiftUI

@main
struct AetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No window scene — menu-bar only (LSUIElement).
        Settings {
            SettingsView()
        }
    }
}
