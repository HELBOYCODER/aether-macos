import Foundation
import NetworkExtension

@MainActor
final class PacketTunnelManager: ObservableObject {
    static let shared = PacketTunnelManager()

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var errorMessage: String?

    private var manager: NETunnelProviderManager?

    private init() {}

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let selected = managers.first ?? NETunnelProviderManager()
            if selected.protocolConfiguration == nil {
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = "com.cluvex.aether.PacketTunnel"
                proto.serverAddress = "Aether"
                proto.providerConfiguration = [
                    "upstreamHost": "127.0.0.1",
                    "upstreamPort": 1819,
                    "mtu": 1280
                ]
                selected.protocolConfiguration = proto
                selected.localizedDescription = "Aether"
                selected.isEnabled = true
                manager = selected
                try await selected.saveToPreferences()
                try await selected.loadFromPreferences()
            } else {
                manager = selected
            }

            status = selected.connection.status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(upstreamHost: String, upstreamPort: Int) async {
        do {
            if manager == nil { await load() }
            guard let manager else { throw NSError(domain: "Aether", code: 1, userInfo: [NSLocalizedDescriptionKey: "VPN configuration unavailable"]) }
            let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.cluvex.aether.PacketTunnel"
            proto.serverAddress = upstreamHost
            proto.providerConfiguration = [
                "upstreamHost": upstreamHost,
                "upstreamPort": upstreamPort,
                "mtu": 1280
            ]
            manager.protocolConfiguration = proto
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            status = manager.connection.status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
    }
}
