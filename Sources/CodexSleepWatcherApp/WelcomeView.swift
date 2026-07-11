import AppKit
import SwiftUI

struct WelcomeView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Sleep Watcher").font(.largeTitle.bold())
                    Text("让任务完成后，Mac 自动休眠").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                step("1", "在菜单栏找到月亮图标")
                step("2", "安装 Hooks，并在 Codex 中审阅和信任")
                step("3", "刷新会话，选择需要观测的目标")
                step("4", "目标停止后，Mac 将按设置真实休眠")
            }

            Text("提示：你可以随时从月亮菜单中打开“使用说明…”。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("开始使用", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 520)
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.indigo.opacity(0.14)))
            Text(title)
        }
    }
}

@MainActor
final class WelcomeWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowPresenter()
    private var window: NSWindow?
    private var onDismiss: (() -> Void)?

    func show(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用 Codex Sleep Watcher"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: WelcomeView { [weak window] in window?.close() })
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss?()
        onDismiss = nil
        window = nil
    }
}
