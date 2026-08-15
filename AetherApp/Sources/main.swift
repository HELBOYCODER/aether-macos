import SwiftUI
import AppKit

@main
enum AetherEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only
        app.run()
    }
}
