import SwiftUI

struct LogView: View {
    @State private var lines: [String] = AetherManager.shared.recentLog()
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(8)
            }
            .onReceive(timer) { _ in
                lines = AetherManager.shared.recentLog()
                if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .frame(width: 560, height: 380)
        .background(Color(NSColor.textBackgroundColor))
    }
}

final class LogWindow {
    static let shared = LogWindow()
    private var win: NSWindow?
    func show() {
        if win == nil {
            let vc = NSHostingController(rootView: LogView())
            win = NSWindow(contentViewController: vc)
            win?.styleMask = [.titled, .closable, .resizable]
            win?.center()
        }
        win?.makeKeyAndOrderFront(nil)
    }
}
