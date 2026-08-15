import AppKit
import SwiftUI

/// Menu-bar controller: status item with connect/disconnect, status, quick
/// protocol/scan picker, settings, and a live log view.
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private let manager = AetherManager.shared

    func build() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "Aether")
            btn.image?.isTemplate = true
        }
        rebuildMenu()
        manager.onStateChange = { [weak self] in self?.rebuildMenu() }
        manager.onLog = { [weak self] _ in self?.rebuildMenu() }
    }

    private func rebuildMenu() {
        let m = NSMenu()
        let state = manager.state

        let title = NSLocalizedString("Aether", comment: "")
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Aether — \(state.label)",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        m.addItem(header)
        m.addItem(.separator())

        let toggle = NSMenuItem(
            title: state == .connected || state == .connecting ? "Disconnect" : "Connect",
            action: #selector(toggle(_:)), keyEquivalent: ""
        )
        toggle.target = self
        m.addItem(toggle)

        // Protocol submenu
        let proto = NSMenu()
        for p in AetherManager.ProtocolKind.allCases {
            let item = NSMenuItem(title: p.rawValue.capitalized, action: #selector(setProto(_:)), keyEquivalent: "")
            item.representedObject = p
            item.target = self
            item.state = manager.settings.protocol == p ? .on : .off
            proto.addItem(item)
        }
        let protoItem = NSMenuItem(title: "Protocol", action: nil, keyEquivalent: "")
        protoItem.submenu = proto
        m.addItem(protoItem)

        // Scan mode submenu
        let scan = NSMenu()
        for s in AetherManager.ScanMode.allCases {
            let item = NSMenuItem(title: s.rawValue.capitalized, action: #selector(setScan(_:)), keyEquivalent: "")
            item.representedObject = s
            item.target = self
            item.state = manager.settings.scan == s ? .on : .off
            scan.addItem(item)
        }
        let scanItem = NSMenuItem(title: "Scan mode", action: nil, keyEquivalent: "")
        scanItem.submenu = scan
        m.addItem(scanItem)

        m.addItem(.separator())
        let log = NSMenuItem(title: "Show Log", action: #selector(openLog(_:)), keyEquivalent: "")
        log.target = self
        m.addItem(log)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        m.addItem(settings)
        let quit = NSMenuItem(title: "Quit Aether", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)

        statusItem.menu = m
    }

    @objc private func toggle(_ sender: Any) {
        if manager.state == .connected || manager.state == .connecting { manager.stop() }
        else { manager.start() }
    }
    @objc private func setProto(_ sender: NSMenuItem) {
        if let p = sender.representedObject as? AetherManager.ProtocolKind {
            manager.settings.protocol = p; manager.persist(); rebuildMenu()
        }
    }
    @objc private func setScan(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? AetherManager.ScanMode {
            manager.settings.scan = s; manager.persist(); rebuildMenu()
        }
    }
    @objc private func openLog(_ sender: Any) { LogWindow.shared.show() }
    @objc private func openSettings(_ sender: Any) { NSApp.activate(ignoringOtherApps: true); SettingsWindow.shared.show() }
}
