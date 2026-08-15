import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menu = MenuBarController()
    private let manager = AetherManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.build()
        manager.startOnLaunchIfEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stop()
    }
}
