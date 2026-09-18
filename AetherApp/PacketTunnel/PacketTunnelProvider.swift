import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var settings: NEPacketTunnelNetworkSettings?
    private var packetBridge: AetherPacketBridge?
    private var stopped = false
    private var hevRunning = false
    private var bypassIPs: [String] = []

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        stopped = false

        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        bypassIPs = (config["bypassIPs"] as? [String]) ?? []
        let socksHost = (config["socksHost"] as? String) ?? "127.0.0.1"
        let socksPort = (config["socksPort"] as? Int) ?? 1819
        let mtu = max(576, min((config["mtu"] as? Int) ?? 1320, 9000))

        let network = makeNetworkSettings(mtu: mtu)

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

            do {
                let bridge = try AetherPacketBridge(
                    flow: self.packetFlow,
                    mtu: mtu,
                    failure: { [weak self] in
                        self?.log("packet bridge failed")
                        self?.cancelTunnelWithError(NSError(
                            domain: "AetherPacketTunnel",
                            code: 1003,
                            userInfo: [NSLocalizedDescriptionKey: "Packet bridge stopped"]
                        ))
                    }
                )
                self.packetBridge = bridge

                let hevConfig = self.makeHEVConfig(
                    socksHost: socksHost,
                    socksPort: socksPort,
                    mtu: mtu
                )

                let result = hevConfig.withCString { ptr in
                    aether_hev_start(ptr, hevConfig.utf8.count, bridge.workerFD)
                }

                guard result == 0 else {
                    bridge.shutdown(afterHEVStopped: true)
                    self.packetBridge = nil
                    throw NSError(
                        domain: "AetherPacketTunnel",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to start HEV dataplane"]
                    )
                }

                bridge.start()
                self.hevRunning = true
                self.log("HEV dataplane started on public packetFlow bridge")
                completionHandler(nil)
            } catch {
                self.packetBridge?.shutdown(afterHEVStopped: true)
                self.packetBridge = nil
                completionHandler(error)
            }
        }
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)? = nil) {
        guard
            let object = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
            object["type"] as? String == "bypassIPs",
            let ips = object["ips"] as? [String]
        else {
            completionHandler?(Data("ignored".utf8))
            return
        }

        bypassIPs = Array(Set(ips.filter { !$0.isEmpty })).sorted()
        if let mtu = settings?.mtu?.intValue {
            applyNetworkSettings(mtu: mtu)
        }
        completionHandler?(Data("ok".utf8))
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        if hevRunning {
            aether_hev_stop()
            hevRunning = false
        }
        packetBridge?.shutdown(afterHEVStopped: true)
        packetBridge = nil
        completionHandler()
    }

    private func makeNetworkSettings(mtu: Int) -> NEPacketTunnelNetworkSettings {
        let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        network.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(
            addresses: ["198.18.0.1"],
            subnetMasks: ["255.255.0.0"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        var excludedIPv4 = [
            NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.255.0.0")
        ]
        for ip in bypassIPs where !ip.contains(":") {
            excludedIPv4.append(
                NEIPv4Route(destinationAddress: ip, subnetMask: "255.255.255.255")
            )
        }
        ipv4.excludedRoutes = excludedIPv4
        network.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(
            addresses: ["fd00::1"],
            networkPrefixLengths: [64]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        var excludedIPv6 = [
            NEIPv6Route(destinationAddress: "fd00::", networkPrefixLength: 64)
        ]
        for ip in bypassIPs where ip.contains(":") {
            excludedIPv6.append(
                NEIPv6Route(destinationAddress: ip, networkPrefixLength: 128)
            )
        }
        ipv6.excludedRoutes = excludedIPv6
        network.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        network.dnsSettings = dns
        return network
    }

    private func applyNetworkSettings(mtu: Int) {
        guard !stopped else { return }
        let network = makeNetworkSettings(mtu: mtu)
        settings = network
        setTunnelNetworkSettings(network) { [weak self] error in
            if let error {
                self?.log("failed to update bypass routes: \(error.localizedDescription)")
            }
        }
    }

    private func makeHEVConfig(socksHost: String, socksPort: Int, mtu: Int) -> String {
        let host = socksHost
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let port = max(1, min(socksPort, 65535))

        return """
        tunnel:
          mtu: \(mtu)
          ipv4: 198.18.0.1
          ipv6: 'fd00::1'

        socks5:
          address: '\(host)'
          port: \(port)
          udp: 'udp'

        mapdns:
          address: 198.18.0.2
          port: 53
          network: 100.64.0.0
          netmask: 255.192.0.0
          cache-size: 10000
          nat64-prefix: 64:ff9b::/96

        misc:
          log-level: warn
          connect-timeout: 5000
          read-write-timeout: 60000
          udp-read-write-timeout: 180000
        """
    }

    private func log(_ message: String) {
        NSLog("[AetherPacketTunnel] %@", message)
    }
}
