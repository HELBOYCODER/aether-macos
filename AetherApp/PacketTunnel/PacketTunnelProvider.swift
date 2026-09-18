import Foundation
import Network
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var settings: NEPacketTunnelNetworkSettings?
    private var controlConnection: NWConnection?
    private var stopped = false
    private var packetReadActive = false
    private var hevActive = false

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        stopped = false

        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let upstreamHost = (config["upstreamHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamPort = (config["upstreamPort"] as? Int) ?? 443

        let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: upstreamHost?.isEmpty == false ? upstreamHost! : "127.0.0.1")
        network.mtu = NSNumber(value: (config["mtu"] as? Int) ?? 1280)
        network.ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        network.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        network.ipv4Settings?.excludedRoutes = [
            NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.255.0.0")
        ]
        network.dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        network.dnsSettings?.matchDomains = [""]

        settings = network
        setTunnelNetworkSettings(network) { [weak self] error in
            guard let self else { return completionHandler(error) }
            if let error {
                completionHandler(error)
                return
            }

            self.packetReadActive = true
            self.readPackets()
            self.startControlProbe(host: upstreamHost ?? "127.0.0.1", port: upstreamPort)
            self.osLog("Network Extension configured; HEV bridge is not embedded yet")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        packetReadActive = false
        hevActive = false
        controlConnection?.cancel()
        controlConnection = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)? = nil) {
        // Reserved for future control-plane messages from the containing app.
        completionHandler?(Data("ok".utf8))
    }

    private func readPackets() {
        guard !stopped, packetReadActive else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, !self.stopped, self.packetReadActive else { return }

            // The packet flow is intentionally drained continuously. The actual
            // packet-to-SOCKS dataplane is provided by the HEV bridge added in
            // the next integration stage, so packets are not reinjected here.
            if !packets.isEmpty {
                self.osLog("received \(packets.count) packet(s) before dataplane bridge")
            }
            self.readPackets()
        }
    }

    private func startControlProbe(host: String, port: Int) {
        guard !stopped else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: NWEndpoint.Port(rawValue: UInt16(max(1, min(port, 65535))))!,
                                      using: .tcp)
        controlConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                self.osLog("upstream probe failed: \(error.localizedDescription)")
            case .ready:
                self.osLog("upstream control connection ready")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func osLog(_ message: String) {
        NSLog("[AetherPacketTunnel] %@", message)
    }
}
