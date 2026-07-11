import SwiftUI
import CodexSleepWatcherCore

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        Text(controller.status).font(.headline)
        if controller.sessions.isEmpty { Text("没有找到最近的 Codex 会话，请先创建或运行一个任务。").foregroundStyle(.secondary) }
        ForEach(controller.sessions) { session in
            Button {
                controller.select(session)
            } label: {
                VStack(alignment: .leading) {
                    Text("● \(session.name) — \(session.status.displayName)")
                    Text("\(session.cwd) · \(session.id.short)").font(.caption)
                }
            }.disabled(controller.selected == session.id)
        }
        Divider()
        Button("刷新会话") { Task { await controller.refresh() } }
        Button("安装 / 更新 Codex Hooks") { controller.installHooks() }
        Button("卸载 Codex Hooks") { controller.uninstallHooks() }
        if controller.selected != nil { Button("取消观测") { controller.cancel() } }
        Picker("休眠延迟", selection: $controller.delaySeconds) {
            Text("0 秒").tag(0); Text("15 秒").tag(15); Text("30 秒").tag(30); Text("60 秒").tag(60)
        }
        Toggle("其他会话仍运行时延后休眠", isOn: $controller.waitForOthers)
        Toggle("保持屏幕常亮", isOn: $controller.keepDisplayAwake)
        Divider()
        Button("立即休眠") { controller.sleepNow() }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
