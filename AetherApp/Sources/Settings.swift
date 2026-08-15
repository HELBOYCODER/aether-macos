import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsVM()
    var body: some View {
        Form {
            Section("Connection") {
                Picker("Protocol", selection: $vm.settings.protocol) {
                    ForEach(AetherManager.ProtocolKind.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized)
                    }
                }
                Picker("Scan mode", selection: $vm.settings.scan) {
                    ForEach(AetherManager.ScanMode.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized)
                    }
                }
                Picker("Obfuscation", selection: $vm.settings.obfuscation) {
                    ForEach(["off", "light", "balanced", "aggressive"], id: \.self) { o in
                        Text(o.capitalized)
                    }
                }
            }
            Section("Proxy") {
                Toggle("Bind HTTP proxy", isOn: $vm.settings.bindHTTP)
                Stepper("SOCKS port: \(vm.settings.socksPort)", value: $vm.settings.socksPort, in: 1024...65535)
                if vm.settings.bindHTTP {
                    Stepper("HTTP port: \(vm.settings.httpProxyPort)", value: $vm.settings.httpProxyPort, in: 1024...65535)
                }
                Toggle("Set system proxy (current Wi-Fi)", isOn: $vm.settings.systemProxy)
            }
            Section("Behaviour") {
                Toggle("Connect on launch", isOn: $vm.settings.launchOnStart)
                TextField("Extra args", text: $vm.settings.extraArgs)
                    .textFieldStyle(.roundedBorder)
            }
            Section {
                Button("Save") { vm.save() }
            }
        }
        .frame(width: 420, height: 340)
        .padding()
        .navigationTitle("Aether Settings")
    }
}

final class SettingsVM: ObservableObject {
    @Published var settings: AetherManager.Settings
    init() { settings = AetherManager.shared.settings }
    func save() { AetherManager.shared.settings = settings; AetherManager.shared.persist() }
}

struct SettingsWindow: NSViewRepresentable {
    static let shared = WindowHolder()
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
final class WindowHolder {
    static let shared = WindowHolder()
    private var win: NSWindow?
    func show() {
        if win == nil {
            let vc = NSHostingController(rootView: SettingsView())
            win = NSWindow(contentViewController: vc)
            win?.styleMask = [.titled, .closable]
            win?.center()
        }
        win?.makeKeyAndOrderFront(nil)
    }
}
