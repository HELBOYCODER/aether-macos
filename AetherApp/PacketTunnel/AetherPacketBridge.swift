import Foundation
import NetworkExtension
import Darwin

protocol AetherPacketFlow: AnyObject {
    func readPackets(completionHandler: @escaping @Sendable ([Data], [NSNumber]) -> Void)
    @discardableResult
    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) -> Bool
}

extension NEPacketTunnelFlow: AetherPacketFlow {}

/// Public Network Extension packetFlow <-> HEV adapter.
/// HEV expects Darwin utun framing: 4-byte address family followed by the IP packet.
/// This bridge keeps the Network Extension API public and owns both socketpair FDs.
final class AetherPacketBridge: @unchecked Sendable {
    let workerFD: Int32
    private let bridgeFD: Int32
    private let flow: AetherPacketFlow
    private let mtu: Int
    private let failure: () -> Void
    private let queue = DispatchQueue(label: "com.cluvex.aether.packet-bridge", qos: .userInitiated)

    private var source: DispatchSourceRead?
    private var active = false
    private var closed = false
    private var readPending = false
    private var generation = 0
    private var pendingFrames: [Data] = []
    private var pendingIndex = 0
    private var pendingBytes = 0
    private var retry: DispatchWorkItem?

    private static let maxPendingBytes = 4 * 1024 * 1024
    private static let maxPendingPackets = 4096

    init(flow: AetherPacketFlow, mtu: Int, failure: @escaping () -> Void) throws {
        self.flow = flow
        self.mtu = mtu
        self.failure = failure

        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        for fd in fds {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0,
                  fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
                  fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                Darwin.close(fds[0])
                Darwin.close(fds[1])
                throw error
            }

            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE,
                           &noSigPipe,
                           socklen_t(MemoryLayout.size(ofValue: noSigPipe)))

            for option in [SO_SNDBUF, SO_RCVBUF] {
                var configured = false
                for capacity in [512, 256, 128, 64] {
                    var bytes = Int32(capacity * 1024)
                    if setsockopt(fd, SOL_SOCKET, option, &bytes,
                                  socklen_t(MemoryLayout.size(ofValue: bytes))) == 0 {
                        configured = true
                        break
                    }
                }
                guard configured else {
                    let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOBUFS)
                    Darwin.close(fds[0])
                    Darwin.close(fds[1])
                    throw error
                }
            }
        }

        bridgeFD = fds[0]
        workerFD = fds[1]

        let readSource = DispatchSource.makeReadSource(fileDescriptor: bridgeFD, queue: queue)
        readSource.setEventHandler { [weak self] in self?.receiveFromHEV() }
        let ownedFD = bridgeFD
        readSource.setCancelHandler {
            Darwin.close(ownedFD)
        }
        source = readSource
        readSource.resume()
    }

    func start() {
        queue.async {
            guard !self.closed else { return }
            self.active = true
            self.generation += 1
            self.clearPending()
            self.drain(self.bridgeFD)
            self.drain(self.workerFD)
            self.readFromFlow()
        }
    }

    func shutdown(afterHEVStopped: Bool = false) {
        queue.sync {
            guard !closed else { return }
            active = false
            generation += 1
            clearPending()
            closed = true
            source?.cancel()
            source = nil
            if afterHEVStopped {
                Darwin.close(workerFD)
            } else {
                Darwin.close(workerFD)
            }
        }
    }

    private func readFromFlow() {
        guard active, !closed, !readPending, pendingFrames.isEmpty else { return }
        readPending = true
        let expectedGeneration = generation

        flow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.queue.async {
                self.readPending = false
                guard self.active, !self.closed, self.generation == expectedGeneration else { return }
                guard packets.count == protocols.count,
                      packets.count <= Self.maxPendingPackets else {
                    self.fail()
                    return
                }

                for (packet, proto) in zip(packets, protocols) {
                    guard let frame = Self.encode(packet, family: proto.int32Value, mtu: self.mtu) else {
                        continue
                    }
                    guard self.pendingBytes + frame.count <= Self.maxPendingBytes else {
                        self.fail()
                        return
                    }
                    self.pendingFrames.append(frame)
                    self.pendingBytes += frame.count
                }
                self.flushPending()
            }
        }
    }

    private func flushPending() {
        guard active, !closed else { return }

        for _ in 0..<256 {
            guard pendingIndex < pendingFrames.count else {
                clearPending()
                readFromFlow()
                return
            }

            let frame = pendingFrames[pendingIndex]
            let result = frame.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return send(bridgeFD, base, raw.count, 0)
            }

            if result < 0 {
                if errno == EINTR { continue }
                guard errno == EAGAIN || errno == ENOBUFS else {
                    fail()
                    return
                }
                scheduleRetry()
                return
            }

            guard result == frame.count else {
                fail()
                return
            }

            pendingIndex += 1
            pendingBytes -= frame.count
        }

        scheduleRetry(delay: .nanoseconds(0))
    }

    private func scheduleRetry(delay: DispatchTimeInterval = .milliseconds(1)) {
        guard retry == nil else { return }
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.retry = nil
            self.flushPending()
        }
        retry = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func receiveFromHEV() {
        guard active, !closed else { return }

        var buffer = [UInt8](repeating: 0, count: mtu + 4)
        var packets: [Data] = []
        var protocols: [NSNumber] = []

        for _ in 0..<256 {
            let count = recv(bridgeFD, &buffer, buffer.count, 0)
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { break }
                fail()
                return
            }
            guard let decoded = Self.decode(Data(buffer.prefix(count)), mtu: mtu) else {
                fail()
                return
            }
            packets.append(decoded.packet)
            protocols.append(NSNumber(value: decoded.family))
        }

        if !packets.isEmpty {
            guard flow.writePackets(packets, withProtocols: protocols) else {
                fail()
                return
            }
        }
    }

    private func clearPending() {
        retry?.cancel()
        retry = nil
        pendingFrames.removeAll(keepingCapacity: false)
        pendingIndex = 0
        pendingBytes = 0
    }

    private func drain(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: mtu + 4)
        while recv(fd, &buffer, buffer.count, 0) >= 0 {}
    }

    private func fail() {
        guard active else { return }
        active = false
        generation += 1
        clearPending()
        failure()
    }

    private static func encode(_ packet: Data, family: Int32, mtu: Int) -> Data? {
        guard packet.count <= mtu, let first = packet.first else { return nil }
        guard (family == AF_INET && first >> 4 == 4) ||
              (family == AF_INET6 && first >> 4 == 6) else { return nil }

        var value = UInt32(family).bigEndian
        var frame = withUnsafeBytes(of: &value) { Data($0) }
        frame.append(packet)
        return frame
    }

    private static func decode(_ frame: Data, mtu: Int) -> (packet: Data, family: Int32)? {
        guard frame.count >= 4, frame.count <= mtu + 4 else { return nil }
        let family = frame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard family == UInt32(AF_INET) || family == UInt32(AF_INET6) else { return nil }

        let packet = Data(frame.dropFirst(4))
        guard packet.count <= mtu, let first = packet.first else { return nil }
        guard (family == UInt32(AF_INET) && first >> 4 == 4) ||
              (family == UInt32(AF_INET6) && first >> 4 == 6) else { return nil }

        return (packet, Int32(family))
    }
}
