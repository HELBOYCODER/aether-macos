import Foundation

/// Enables/disables macOS system-wide proxy via `networksetup` (no root needed
/// for the current user's network services). Only binds 127.0.0.1 — never 0.0.0.0.
final class ProxyManager {
    static let shared = ProxyManager()
    private var serviceName: String?

    func enable(socks port: Int) {
        guard let svc = defaultService() else { return }
        self.serviceName = svc
        let _ = run("networksetup", ["-setsocksfirewallproxy", svc, "127.0.0.1", "\(port)"])
        let _ = run("networksetup", ["-setsocksfirewallproxystate", svc, "on"])
    }

    func disable() {
        guard let svc = serviceName ?? defaultService() else { return }
        let _ = run("networksetup", ["-setsocksfirewallproxystate", svc, "off"])
    }

    private func defaultService() -> String? {
        let out = run("networksetup", ["-listallnetworkservices"])
        let services = out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        // Prefer Wi-Fi / Ethernet-like names first.
        return services.first { $0.lowercased().contains("wi-fi") || $0.lowercased().contains("wifi") }
            ?? services.first { $0.lowercased().contains("ethernet") }
            ?? services.first
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/\(tool)")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
