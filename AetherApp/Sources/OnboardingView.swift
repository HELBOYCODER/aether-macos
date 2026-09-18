import SwiftUI

/// First-run onboarding for Aether and SSH dynamic SOCKS tunneling.
struct OnboardingView: View {
    @State private var seen = UserDefaults.standard.bool(forKey: "aether.onboarded")

    var body: some View {
        if seen {
            EmptyView()
        } else {
            VStack(spacing: 18) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Welcome to Aether")
                    .font(.title.bold())

                Text("Choose Aether or an SSH tunnel. SSH mode uses OpenSSH dynamic forwarding and exposes a local SOCKS5 proxy at 127.0.0.1.")
                    .multilineTextAlignment(.center)
                    .frame(width: 340)
                    .foregroundColor(.secondary)

                Button("Open Settings") {
                    UserDefaults.standard.set(true, forKey: "aether.onboarded")
                    seen = true
                    SettingsWindow.shared.show()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(width: 400, height: 300)
        }
    }
}

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var win: NSWindow?

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "aether.onboarded") else { return }
        let vc = NSHostingController(rootView: OnboardingView())
        win = NSWindow(contentViewController: vc)
        win?.styleMask = [.titled]
        win?.center()
        win?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
