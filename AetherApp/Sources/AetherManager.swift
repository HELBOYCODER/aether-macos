import Foundation
import AppKit

/// Wraps the bundled `aether` CLI: launches it as a child process, streams its
/// stdout/stderr, and exposes a simple connect/disconnect state machine.
final class AetherManager {
    enum State: Equatable { case idle, connecting, connected, error(String) }
    enum ProtocolKind: String, CaseIterable, Codable { case masque, wg, gool }
    enum ScanMode: String, CaseIterable, Codable { case turbo, balanced, thorough, stealth, ironclad }

    struct Settings: Codable {
        var `protocol`: ProtocolKind = .masque
        var scan: ScanMode = .balanced
        var obfuscation: String = "balanced"   // off | light | balanced | aggressive
        var bindHTTP: Bool = false
        var launchOnStart: Bool = true
        var systemProxy: Bool = false
        var httpProxyPort: Int = 1820
        var socksPort: Int = 1819
        var extraArgs: String = ""
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
        } else { settings = Settings() }
    }

    func persist() {
        if let d = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(d, forKey: defaultsKey)
        }
    }

    func startOnLaunchIfEnabled() {
        if settings.launchOnStart { start() }
    }

    func binaryPath() -> String? {
        // Bundled helper next to the executable in the app bundle.
        let exeDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("aether")
        return FileManager.default.fileExists(atPath: exeDir.path) ? exeDir.path : nil
    }

    func start() {
        queue.async { self._start() }
    }

    private func _start() {
        guard process == nil else { return }
        guard let bin = binaryPath() else {
            setState(.error("aether binary not found in bundle")); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = buildArgs()

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
            str.enumerateLines { line, _ in self?.appendLog(line) }
            self?.inferState(from: str)
        }
        p.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.process = nil
                self?.setStateIf(.connecting, to: .idle)
                self?.setStateIf(.connected, to: .idle)
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

    func stop() {
        queue.async {
            self.process?.terminationHandler = nil
            self.process?.terminate()
            self.process = nil
            self.setState(.idle)
            ProxyManager.shared.disable()
        }
    }

    private func buildArgs() -> [String] {
        var a: [String] = []
        switch settings.protocol {
        case .masque: a.append("--masque")
        case .wg: a.append("--wg")
        case .gool: a.append("--gool")
        }
        a += ["--scan", settings.scan.rawValue]
        a += ["--noize", settings.obfuscation]
        a += ["--bind", "127.0.0.1:\(settings.socksPort)"]
        if settings.bindHTTP { a += ["--http-proxy", "127.0.0.1:\(settings.httpProxyPort)"] }
        if !settings.extraArgs.isEmpty {
            a += settings.extraArgs.split(separator: " ").map(String.init)
        }
        return a
    }

    private func inferState(from line: String) {
        let l = line.lowercased()
        if l.contains("tunnel validated") || l.contains("socks5") && l.contains("available") {
            setState(.connected)
            if settings.systemProxy { ProxyManager.shared.enable(socks: settings.socksPort) }
        } else if l.contains("error") || l.contains("failed") {
            // only flip to error if not already connected (reconnect chatter)
            if state != .connected { setState(.error(line.trimmingCharacters(in: .whitespacesAndNewlines))) }
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
    private func setStateIf(_ from: State, to: State) {
        if state == from { setState(to) }
    }
}

extension AetherManager.State {
    var label: String {
        switch self {
        case .idle: return "Off"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let e): return "Error"
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
