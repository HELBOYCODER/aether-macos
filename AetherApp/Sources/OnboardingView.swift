import SwiftUI

/// First-run onboarding: explains what Aether does and the one-click connect.
struct OnboardingView: View {
    @State private var seen = UserDefaults.standard.bool(forKey: "aether.onboarded")
    var body: some View {
        if seen { EmptyView() }
        else {
            VStack(spacing: 18) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Welcome to Aether")
                    .font(.title.bold())
                Text("Aether builds an encrypted tunnel out of restricted networks and exposes a local SOCKS5 proxy at 127.0.0.1:1819.")
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
                    .foregroundColor(.secondary)
                Button("Start using Aether") {
                    UserDefaults.standard.set(true, forKey: "aether.onboarded")
                    seen = true
                    AetherManager.shared.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(width: 380, height: 300)
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
    }
}
