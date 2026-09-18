import Foundation
import NetworkExtension

@MainActor
final class PacketTunnelManager: ObservableObject {
    static let shared = PacketTunnelManager()

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var pendingBypassIPs: [String] = []

    private init() {}

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let selected = managers.first ?? NETunnelProviderManager()

            let proto: NETunnelProviderProtocol
            if let existing = selected.protocolConfiguration as? NETunnelProviderProtocol {
                proto = existing
            } else {
                proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = "com.cluvex.aether.PacketTunnel"
                proto.serverAddress = "Aether"
                proto.providerConfiguration = [
                    "upstreamHost": "127.0.0.1",
                    "upstreamPort": AetherManager.shared.settings.socksPort,
                    "mtu": 1320,
                    "socksHost": "127.0.0.1",
                    "socksPort": AetherManager.shared.settings.socksPort,
                    "bypassIPs": []
                ]
                selected.protocolConfiguration = proto
                selected.localizedDescription = "Aether"
                selected.isEnabled = true
                try await selected.saveToPreferences()
                try await selected.loadFromPreferences()
            }

            proto.providerBundleIdentifier = "com.cluvex.aether.PacketTunnel"
            selected.protocolConfiguration = proto
            manager = selected
            status = selected.connection.status
            installStatusObserver(for: selected)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(upstreamHost: String, upstreamPort: Int, mtu: Int = 1320) async {
        do {
            if manager == nil {
                await load()
            }
            guard let manager else {
                throw NSError(
                    domain: "Aether",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "VPN configuration unavailable"]
                )
            }

            if manager.connection.status == .connected || manager.connection.status == .connecting {
                return
            }

            let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol)
                ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.cluvex.aether.PacketTunnel"
            proto.serverAddress = upstreamHost
            proto.providerConfiguration = [
                "upstreamHost": upstreamHost,
                "upstreamPort": upstreamPort,
                "mtu": max(576, min(mtu, 9000)),
                "socksHost": "127.0.0.1",
                "socksPort": AetherManager.shared.settings.socksPort,
                "bypassIPs": []
            ]

            manager.protocolConfiguration = proto
            manager.localizedDescription = "Aether"
            manager.isEnabled = true

            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            installStatusObserver(for: manager)

            try manager.connection.startVPNTunnel()
            status = manager.connection.status
            errorMessage = nil
            if !pendingBypassIPs.isEmpty {
                sendBypassIPs(pendingBypassIPs)
            }
        } catch {
            errorMessage = error.localizedDescription
            status = manager?.connection.status ?? .disconnected
        }
    }

    private func installStatusObserver(for manager: NETunnelProviderManager) {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let connection = notification.object as? NEVPNConnection else { return }
            self.status = connection.status
            if connection.status == .connected, !self.pendingBypassIPs.isEmpty {
                self.sendBypassIPs(self.pendingBypassIPs)
            }
        }
    }

    func updateBypassIPs(_ ips: [String]) {
        let clean = Array(Set(ips.filter {
            !$0.isEmpty && !$0.hasPrefix("127.") && $0 != "::1" && $0 != "0.0.0.0"
        })).sorted()
        pendingBypassIPs = clean

        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else { return }

        sendBypassIPs(clean)
    }

    private func sendBypassIPs(_ clean: [String]) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else { return }

        guard let data = try? JSONSerialization.data(
            withJSONObject: ["type": "bypassIPs", "ips": clean]
        ) else { return }

        do {
            try session.sendProviderMessage(data, responseHandler: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }
}
