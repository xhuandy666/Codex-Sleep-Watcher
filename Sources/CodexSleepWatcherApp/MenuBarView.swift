import SwiftUI
import CodexSleepWatcherCore

struct MenuBarView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(controller.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()
            sessionList
            Divider()
            settings
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 460, height: 600, alignment: .top)
    }

    private var header: some View {
        HStack {
            Label("Codex Sleep Watcher", systemImage: "moon.zzz.fill")
                .font(.headline)
            Spacer()
            Button {
                Task { await controller.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if controller.sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("没有找到会话").font(.headline)
                Text("请先在 Codex 创建或运行一个任务")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 250)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近会话")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(controller.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 320)
                Text("“尚未收到事件”表示尚无 Hook；“状态待确认”会继续阻止自动休眠")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let isSelected = controller.selected == session.id
        return Button {
            controller.select(session)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(statusColor(session.status))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(session.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(projectName(session.cwd)) · \(session.id.short)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isSelected {
                        Label("正在观测", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("休眠延迟")
                Spacer()
                Picker("休眠延迟", selection: $controller.delaySeconds) {
                    Text("0 秒").tag(0)
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }
                .labelsHidden()
                .frame(width: 110)
            }
            Toggle("其他会话仍运行时延后休眠", isOn: $controller.waitForOthers)
            Toggle("保持屏幕常亮", isOn: $controller.keepDisplayAwake)
        }
        .font(.callout)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack {
                Button("安装 / 更新 Hooks") { controller.installHooks() }
                Button("使用说明…") { controller.showWelcome() }
                Spacer()
                if controller.selected != nil {
                    Button("取消观测") { controller.cancel() }
                }
            }
            HStack {
                Button("卸载 Hooks") { controller.uninstallHooks() }
                Spacer()
                Button("立即休眠") { controller.sleepNow() }
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func projectName(_ cwd: String) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .running: .green
        case .waitingOnApproval, .waitingOnUserInput: .orange
        case .staleActive: .yellow
        case .idle: .blue
        case .unknown: .secondary
        }
    }
}
