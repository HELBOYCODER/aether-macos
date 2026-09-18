import Foundation
import Network
import NetworkExtension
import Darwin

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var settings: NEPacketTunnelNetworkSettings?
    private var stopped = false
    private var packetReadActive = false
    private var hevFD: Int32 = -1
    private var hevReadSource: DispatchSourceRead?
    private let packetQueue = DispatchQueue(label: "com.cluvex.aether.packet-tunnel", qos: .userInitiated)

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        stopped = false
        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let socksHost = (config["socksHost"] as? String) ?? "127.0.0.1"
        let socksPort = (config["socksPort"] as? Int) ?? 1080
        let remote = (config["upstreamHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mtu = max(576, min((config["mtu"] as? Int) ?? 1320, 9000))

        let network = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: remote?.isEmpty == false ? remote! : "127.0.0.1"
        )
        network.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.255.0.0")]
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

        settings = network
        setTunnelNetworkSettings(network) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if let error { completionHandler(error); return }

            let hevConfig = self.makeHEVConfig(
                socksHost: socksHost,
                socksPort: socksPort,
                mtu: mtu
            )
            let fd = hevConfig.withCString { ptr in
                aether_hev_start(ptr, hevConfig.utf8.count)
            }
            guard fd >= 0 else {
                self.log("HEV start failed")
                completionHandler(NSError(domain: "AetherPacketTunnel", code: 1001,
                                           userInfo: [NSLocalizedDescriptionKey: "Unable to start HEV dataplane"]))
                return
            }

            self.hevFD = fd
            self.startHEVOutputReader()
            self.packetReadActive = true
            self.readPackets()
            self.log("HEV dataplane started")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        packetReadActive = false
        hevReadSource?.cancel()
        hevReadSource = nil
        aether_hev_stop()
        hevFD = -1
        completionHandler()
    }

    private func makeHEVConfig(socksHost: String, socksPort: Int, mtu: Int) -> String {
        let host = socksHost.replacingOccurrences(of: "\\", with: "")
                         .replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
        let port = max(1, min(socksPort, 65535))
        return """
        tunnel:
          mtu: \(mtu)
          ipv4: 198.18.0.1
          ipv6: 'fd00::1'

        socks5:
          address: \(host)
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

    private func readPackets() {
        guard !stopped, packetReadActive, hevFD >= 0 else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, !self.stopped, self.packetReadActive, self.hevFD >= 0 else { return }
            for (index, packet) in packets.enumerated() {
                guard !packet.isEmpty else { continue }
                let family: UInt32
                if index < protocols.count {
                    family = protocols[index].uint32Value
                } else {
                    family = packet.first.map { (($0 >> 4) == 6) ? UInt32(AF_INET6) : UInt32(AF_INET) } ?? UInt32(AF_INET)
                }
                var frame = Data()
                var netFamily = family.bigEndian
                withUnsafeBytes(of: &netFamily) { frame.append(contentsOf: $0) }
                frame.append(packet)
                let sent = frame.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return send(self.hevFD, base, raw.count, 0)
                }
                if sent != frame.count {
                    self.log("HEV packet send failed: \(String(cString: strerror(errno)))")
                }
            }
            self.readPackets()
        }
    }

    private func startHEVOutputReader() {
        guard hevFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: hevFD, queue: packetQueue)
        source.setEventHandler { [weak self] in
            guard let self, !self.stopped, self.hevFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4 + 65536)
            let count = recv(self.hevFD, &buffer, buffer.count, 0)
            if count <= 0 {
                self.packetReadActive = false
                self.hevReadSource?.cancel()
                self.cancelTunnelWithError(NSError(domain: "AetherPacketTunnel", code: 1002,
                                                    userInfo: [NSLocalizedDescriptionKey: "HEV dataplane stopped"]))
                return
            }
            guard count > 4 else { return }
            let family = UInt32(buffer[0]) << 24 | UInt32(buffer[1]) << 16 |
                         UInt32(buffer[2]) << 8 | UInt32(buffer[3])
            let packet = Data(buffer[4..<count])
            let proto = NSNumber(value: Int(family))
            self.packetFlow.writePackets([packet], withProtocols: [proto])
        }
        source.setCancelHandler { }
        hevReadSource = source
        source.resume()
    }

    private func log(_ message: String) {
        NSLog("[AetherPacketTunnel] %@", message)
    }
}
