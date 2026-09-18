import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var settings: NEPacketTunnelNetworkSettings?
    private var stopped = false
    private var hevRunning = false

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        stopped = false

        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let socksHost = (config["socksHost"] as? String) ?? "127.0.0.1"
        let socksPort = (config["socksPort"] as? Int) ?? 1819
        let mtu = max(576, min((config["mtu"] as? Int) ?? 1320, 9000))

        let network = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        network.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.255.0.0")
        ]
        network.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = [
            NEIPv6Route(destinationAddress: "fd00::", networkPrefixLength: 64)
        ]
        network.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        network.dnsSettings = dns

        setTunnelNetworkSettings(network) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if let error {
                completionHandler(error)
                return
            }

            guard let tunFD = UtunFileDescriptor.from(packetFlow: self.packetFlow) else {
                completionHandler(NSError(
                    domain: "AetherPacketTunnel",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Network Extension utun file descriptor"]
                ))
                return
            }

            let hevConfig = self.makeHEVConfig(
                socksHost: socksHost,
                socksPort: socksPort,
                mtu: mtu
            )

            let result = hevConfig.withCString { ptr in
                aether_hev_start(ptr, hevConfig.utf8.count, tunFD)
            }
            guard result == 0 else {
                completionHandler(NSError(
                    domain: "AetherPacketTunnel",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to start HEV dataplane"]
                ))
                return
            }

            self.hevRunning = true
            self.log("HEV started on Network Extension utun fd \(tunFD)")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        if hevRunning {
            aether_hev_stop()
            hevRunning = false
        }
        completionHandler()
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

private enum UtunFileDescriptor {
    static func from(packetFlow: NEPacketTunnelFlow) -> Int32? {
        if let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            return fd
        }
        if let number = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? NSNumber {
            return number.int32Value
        }
        return nil
    }
}
