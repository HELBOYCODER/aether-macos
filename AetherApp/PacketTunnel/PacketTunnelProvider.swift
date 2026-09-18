import Foundation
import Network
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var settings: NEPacketTunnelNetworkSettings?
    private var controlConnection: NWConnection?
    private var stopped = false
    private var packetReadActive = false

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        stopped = false

        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let host = (config["upstreamHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = (config["upstreamPort"] as? Int) ?? 443
        let mtu = max(576, min((config["mtu"] as? Int) ?? 1320, 9000))

        let network = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: host?.isEmpty == false ? host! : "127.0.0.1"
        )
        network.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(
            addresses: ["198.18.0.1"],
            subnetMasks: ["255.255.0.0"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.255.0.0")
        ]
        network.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        network.dnsSettings = dns

        settings = network
        setTunnelNetworkSettings(network) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if let error {
                completionHandler(error)
                return
            }

            self.packetReadActive = true
            self.readPackets()
            self.startControlProbe(host: host ?? "127.0.0.1", port: port)

            // HEV is linked into the extension target through HEVBridge.c.
            // It still needs the actual NEPacketTunnelProvider packet path adapter;
            // NEPacketTunnelFlow is not a raw BSD TUN descriptor, so passing a
            // fabricated fd here would be unsafe. Keep the route fail-closed until
            // that adapter is implemented.
            self.log("HEV native library linked; packetFlow adapter remains fail-closed")

            // This provider now owns the system route, but intentionally does not
            // claim packet forwarding until the native HEV adapter is linked.
            // Dropping packets prevents accidental clear-net fallback.
            self.log("Tunnel network settings installed; native HEV dataplane pending")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        packetReadActive = false
        controlConnection?.cancel()
        controlConnection = nil
        completionHandler()
    }

    private func readPackets() {
        guard !stopped, packetReadActive else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, !self.stopped, self.packetReadActive else { return }
            if !packets.isEmpty {
                self.log("received \(packets.count) packet(s); no dataplane bridge linked")
            }
            self.readPackets()
        }
    }

    private func startControlProbe(host: String, port: Int) {
        guard !stopped, let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        controlConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.log("upstream control connection ready")
            case .failed(let error):
                self?.log("upstream probe failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func log(_ message: String) {
        NSLog("[AetherPacketTunnel] %@", message)
    }
}
