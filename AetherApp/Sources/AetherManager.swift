import Foundation
import AppKit

/// Wraps either the bundled aether CLI or the system OpenSSH client.
/// SSH mode creates a loopback-only SOCKS5 tunnel with dynamic forwarding.
final class AetherManager {
    enum State: Equatable { case idle, connecting, connected, error(String) }
    enum ConnectionMode: String, CaseIterable, Codable {
        case aether
        case ssh
    }
    enum ProtocolKind: String, CaseIterable, Codable { case masque, wg, gool }
    enum ScanMode: String, CaseIterable, Codable { case turbo, balanced, thorough, stealth, ironclad }

    struct Settings: Codable {
        var mode: ConnectionMode = .aether
        var `protocol`: ProtocolKind = .masque
        var scan: ScanMode = .balanced
        var obfuscation: String = "balanced"
        var bindHTTP: Bool = false
        var launchOnStart: Bool = true
        var systemProxy: Bool = false
        var httpProxyPort: Int = 1820
        var socksPort: Int = 1819
        var extraArgs: String = ""

        // SSH dynamic SOCKS forwarding.
        var sshHost: String = ""
        var sshUser: String = ""
        var sshPort: Int = 22
        var sshIdentityFile: String = ""

        init() {}

        private enum CodingKeys: String, CodingKey {
            case mode, `protocol`, scan, obfuscation, bindHTTP, launchOnStart
            case systemProxy, httpProxyPort, socksPort, extraArgs
            case sshHost, sshUser, sshPort, sshIdentityFile
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decodeIfPresent(ConnectionMode.self, forKey: .mode) ?? .aether
            `protocol` = try c.decodeIfPresent(ProtocolKind.self, forKey: .protocol) ?? .masque
            scan = try c.decodeIfPresent(ScanMode.self, forKey: .scan) ?? .balanced
            obfuscation = try c.decodeIfPresent(String.self, forKey: .obfuscation) ?? "balanced"
            bindHTTP = try c.decodeIfPresent(Bool.self, forKey: .bindHTTP) ?? false
            launchOnStart = try c.decodeIfPresent(Bool.self, forKey: .launchOnStart) ?? true
            systemProxy = try c.decodeIfPresent(Bool.self, forKey: .systemProxy) ?? false
            httpProxyPort = try c.decodeIfPresent(Int.self, forKey: .httpProxyPort) ?? 1820
            socksPort = try c.decodeIfPresent(Int.self, forKey: .socksPort) ?? 1819
            extraArgs = try c.decodeIfPresent(String.self, forKey: .extraArgs) ?? ""
            sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
            sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
            sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
            sshIdentityFile = try c.decodeIfPresent(String.self, forKey: .sshIdentityFile) ?? ""
        }
    }

    static let shared = AetherManager()
    private let defaultsKey = "aether.settings"
    var settings: Settings
    private(set) var state: State = .idle
    private var process: Process?
    private var logLines: [String] = []
    private let logLimit = 2000
    private let queue = DispatchQueue(label: "aether.manager")

    var onStateChange: (() -> Void)?
    var onLog: ((String) -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings()
        }
    }

    func persist() {
        if let d = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(d, forKey: defaultsKey)
        }
    }

    func startOnLaunchIfEnabled() {
        if settings.launchOnStart &&
            (settings.mode == .aether || !settings.sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            start()
        }
    }

    func binaryPath() -> String? {
        let exeDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("aether")
        return FileManager.default.fileExists(atPath: exeDir.path) ? exeDir.path : nil
    }

    func start() {
        queue.async {
            guard self.process == nil else { return }
            if self.settings.mode == .ssh {
                self._startSSH()
            } else {
                self._startAether()
            }
        }
    }

    private func _startAether() {
        guard let bin = binaryPath() else {
            setState(.error("aether binary not found in bundle"))
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = buildAetherArgs()

        let pipe = Pipe()
        attachOutput(pipe, to: p)
        p.terminationHandler = { [weak self] proc in
            self?.queue.async {
                guard let self else { return }
                self.process = nil
                if proc.terminationStatus != 0 {
                    self.setState(.error("aether exited with code \(proc.terminationStatus)"))
                } else {
                    self.setState(.idle)
                }
                ProxyManager.shared.disable()
            }
        }

        do {
            setState(.connecting)
            try p.run()
            process = p
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    private func _startSSH() {
        let host = settings.sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            setState(.error("SSH host is empty"))
            return
        }

        let user = settings.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = user.isEmpty ? host : "\(user)@\(host)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args = [
            "-N",
            "-D", "127.0.0.1:\(settings.socksPort)",
            "-p", "\(settings.sshPort)",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            destination
        ]

        let identity = NSString(string: settings.sshIdentityFile)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            args.insert(contentsOf: ["-i", identity], at: args.count - 1)
        }

        p.arguments = args
        let pipe = Pipe()
        attachOutput(pipe, to: p)
        p.terminationHandler = { [weak self] proc in
            self?.queue.async {
                guard let self else { return }
                self.process = nil
                if proc.terminationStatus != 0 {
                    self.setState(.error("ssh exited with code \(proc.terminationStatus)"))
                } else {
                    self.setState(.idle)
                }
                ProxyManager.shared.disable()
            }
        }

        do {
            setState(.connecting)
            try p.run()
            process = p

            queue.asyncAfter(deadline: .now() + 0.7) { [weak self, weak p] in
                guard let self, let p, p.isRunning, self.process === p else { return }
                self.setState(.connected)
                if self.settings.systemProxy {
                    ProxyManager.shared.enable(socks: self.settings.socksPort)
                }
                self.appendLog("SSH tunnel established: SOCKS5 127.0.0.1:\(self.settings.socksPort)")
            }
        } catch {
            setState(.error(error.localizedDescription))
        }
    }


    /// Starts the macOS Network Extension tunnel around the Aether local SOCKS endpoint.
    func startSystemTunnel() {
        let host = "127.0.0.1"
        let port = settings.socksPort
        DispatchQueue.main.async {
            PacketTunnelManager.shared.start(upstreamHost: host, upstreamPort: port, mtu: 1320)
        }
    }

    func stopSystemTunnel() {
        DispatchQueue.main.async {
            PacketTunnelManager.shared.stop()
        }
    }

    func stop() {
        queue.async {
            self.process?.terminationHandler = nil
            self.process?.terminate()
            self.process = nil
            self.setState(.idle)
            ProxyManager.shared.disable()
        }
    }

    private func buildAetherArgs() -> [String] {
        var a: [String] = []
        switch settings.protocol {
        case .masque: a.append("--masque")
        case .wg: a.append("--wg")
        case .gool: a.append("--gool")
        }
        a += ["--scan", settings.scan.rawValue]
        a += ["--noize", settings.obfuscation]
        a += ["--bind", "127.0.0.1:\(settings.socksPort)"]
        if settings.bindHTTP {
            a += ["--http-proxy", "127.0.0.1:\(settings.httpProxyPort)"]
        }
        if !settings.extraArgs.isEmpty {
            a += settings.extraArgs.split(separator: " ").map(String.init)
        }
        return a
    }

    private func attachOutput(_ pipe: Pipe, to process: Process) {
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
            str.enumerateLines { line, _ in self?.appendLog(line) }
            if self?.settings.mode == .aether {
                self?.inferAetherState(from: str)
            }
        }
    }

    private func inferAetherState(from line: String) {
        let l = line.lowercased()
        if l.contains("tunnel validated") || (l.contains("socks5") && l.contains("available")) {
            setState(.connected)
            if settings.systemProxy {
                ProxyManager.shared.enable(socks: settings.socksPort)
            }
        } else if l.contains("error") || l.contains("failed") {
            if state != .connected {
                setState(.error(line.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    private func appendLog(_ line: String) {
        queue.async {
            self.logLines.append(line)
            if self.logLines.count > self.logLimit { self.logLines.removeFirst() }
            DispatchQueue.main.async { self.onLog?(line) }
        }
    }

    func recentLog() -> [String] { queue.sync { logLines } }

    private func setState(_ s: State) {
        queue.async {
            DispatchQueue.main.async {
                self.state = s
                self.onStateChange?()
            }
        }
    }
}

extension AetherManager.State {
    var label: String {
        switch self {
        case .idle: return "Off"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }

    var color: NSColor {
        switch self {
        case .idle: return .systemGray
        case .connecting: return .systemYellow
        case .connected: return .systemGreen
        case .error: return .systemRed
        }
    }
}
