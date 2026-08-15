import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menu = MenuBarController()
    private let manager = AetherManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
        menu.build()
        OnboardingWindow.shared.showIfNeeded()
        manager.startOnLaunchIfEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stop()
    }
}
