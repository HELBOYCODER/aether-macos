import AppKit
import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsVM()

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Connection type", selection: $vm.settings.mode) {
                    ForEach(AetherManager.ConnectionMode.allCases, id: \.self) { mode in
                        Text(mode == .ssh ? "SSH tunnel" : "Aether")
                            .tag(mode)
                    }
                }

                if vm.settings.mode == .aether {
                    Picker("Protocol", selection: $vm.settings.protocol) {
                        ForEach(AetherManager.ProtocolKind.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized)
                                .tag(p)
                        }
                    }
                    Picker("Scan mode", selection: $vm.settings.scan) {
                        ForEach(AetherManager.ScanMode.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized)
                                .tag(s)
                        }
                    }
                    Picker("Obfuscation", selection: $vm.settings.obfuscation) {
                        ForEach(["off", "light", "balanced", "aggressive"], id: \.self) { o in
                            Text(o.capitalized)
                                .tag(o)
                        }
                    }
                } else {
                    TextField("SSH host", text: $vm.settings.sshHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("SSH user", text: $vm.settings.sshUser)
                        .textFieldStyle(.roundedBorder)
                    Stepper("SSH port: \(vm.settings.sshPort)", value: $vm.settings.sshPort, in: 1...65535)

                    HStack {
                        TextField("Identity file", text: $vm.settings.sshIdentityFile)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { vm.chooseIdentityFile() }
                    }

                    Text("SSH mode uses OpenSSH key/agent authentication. Password prompts are intentionally not handled by the GUI.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Proxy") {
                Toggle("Bind HTTP proxy", isOn: $vm.settings.bindHTTP)
                Stepper("SOCKS port: \(vm.settings.socksPort)", value: $vm.settings.socksPort, in: 1024...65535)
                if vm.settings.bindHTTP && vm.settings.mode == .aether {
                    Stepper("HTTP port: \(vm.settings.httpProxyPort)", value: $vm.settings.httpProxyPort, in: 1024...65535)
                }
                Toggle("Set system proxy (current Wi-Fi)", isOn: $vm.settings.systemProxy)
            }

            Section("Behaviour") {
                Toggle("Connect on launch", isOn: $vm.settings.launchOnStart)
                if vm.settings.mode == .aether {
                    TextField("Extra args", text: $vm.settings.extraArgs)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                Button("Save") { vm.save() }
            }
        }
        .frame(width: 520, height: vm.settings.mode == .ssh ? 470 : 390)
        .padding()
        .navigationTitle("Aether Settings")
    }
}

final class SettingsVM: ObservableObject {
    @Published var settings: AetherManager.Settings

    init() {
        settings = AetherManager.shared.settings
    }

    func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH private key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.sshIdentityFile = url.path
        }
    }

    func save() {
        AetherManager.shared.settings = settings
        AetherManager.shared.persist()
    }
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
            win?.styleMask = [.titled, .closable, .resizable]
            win?.center()
        }
        win?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
