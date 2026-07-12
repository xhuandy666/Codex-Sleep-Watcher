import Foundation
import SwiftUI
import CodexSleepWatcherCore

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var selected: SessionID?
    @Published private(set) var status = "正在初始化"
    @Published private(set) var countdown: Int?
    @Published var delaySeconds: Int
    @Published var waitForOthers: Bool
    @Published var keepDisplayAwake: Bool

    private let settings = SettingsStore()
    private let appServer = AppServerClient()
    private let registry = SessionRegistry()
    private let receiver = HookEventReceiver()
    private let power = PowerAssertionController()
    private let sleeper: any SystemSleeping
    private var eventTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var waitingAfterTargetStop = false
    private var hasStarted = false
    private var observation = ObservationFence()

    init() {
        delaySeconds = settings.delaySeconds
        waitForOthers = settings.waitForOtherSessions
        keepDisplayAwake = settings.keepDisplayAwake
        sleeper = CommandLine.arguments.contains("--disable-real-sleep") ? LoggingSleeper() : MacSystemSleeper()
        if !settings.hasShownWelcome {
            DispatchQueue.main.async { [weak self] in self?.showWelcome() }
        }
    }

    func showWelcome() {
        WelcomeWindowPresenter.shared.show { [weak self] in self?.settings.hasShownWelcome = true }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let stream = try receiver.events()
            eventTask = Task { [weak self] in for await event in stream { await self?.handle(event) } }
            try await appServer.start()
            status = "请选择一个运行中的会话"
            await refresh()
        } catch {
            hasStarted = false
            eventTask?.cancel()
            eventTask = nil
            status = "初始化失败：\(error.localizedDescription)"
        }
    }

    func refresh() async {
        do {
            let response = try await appServer.listThreads()
            let recent = SessionDiscoveryService.mapRecentThreads(response.data)
            await registry.refresh(from: recent, preserving: selected)
            sessions = await registry.sessions()
        } catch { status = "读取会话失败：\(error.localizedDescription)" }
    }

    func installHooks() {
        do {
            guard let helper = HookHelperLocator.locate(
                bundleURL: Bundle.main.bundleURL,
                executableURL: Bundle.main.executableURL
            ) else { throw CocoaError(.fileNoSuchFile) }
            try HookInstaller().install(helperPath: helper.path)
            status = "六个 Hooks 已安装/更新；请在 Codex 中重新审阅并信任"
        } catch { status = "Hooks 安装失败：\(error.localizedDescription)" }
    }

    func uninstallHooks() {
        do { try HookInstaller().uninstall(); status = "Codex Hooks 已卸载" }
        catch { status = "Hooks 卸载失败：\(error.localizedDescription)" }
    }

    func select(_ session: SessionSummary) {
        guard selected != session.id else { return }
        cancelPendingSleep()
        power.stop()
        observation.cancel()
        selected = nil
        do {
            try power.start(keepDisplayAwake: keepDisplayAwake)
            observation.select(session.id)
            selected = session.id; status = "正在观测：\(session.name)"
        } catch { status = "无法阻止休眠：\(error.localizedDescription)" }
    }

    func cancel() {
        cancelPendingSleep(); observation.cancel(); selected = nil; power.stop(); status = "已取消观测"
    }

    func sleepNow() { do { try sleeper.sleepNow() } catch { status = "休眠失败：\(error.localizedDescription)" } }

    private func handle(_ event: HookEvent) async {
        let accepted = await registry.apply(event)
        guard accepted else {
#if DEBUG
            print("CSW_EVENT ignored stale kind=\(event.kind.rawValue) id=\(event.sessionID.short)")
#endif
            return
        }
        sessions = await registry.sessions()
#if DEBUG
        let project = URL(fileURLWithPath: event.cwd).lastPathComponent
        let visible = sessions.map { "\($0.id.short):\($0.status.displayName)" }.joined(separator: ",")
        print("CSW_EVENT kind=\(event.kind.rawValue) id=\(event.sessionID.short) project=\(project) visible=[\(visible)]")
#endif
        guard let context = observation.token, selected == context.target else { return }
        guard event.sessionID == context.target else {
            await handleNonTargetEvent(context: context)
            return
        }

        switch event.kind.targetDecision {
        case .activity:
            cancelPendingSleep()
            status = "目标会话继续运行"
        case .waitingForAuthorization:
            cancelPendingSleep()
            status = "目标等待授权，保持唤醒"
        case .stopped:
            let others = await registry.runningSessions().filter { $0.id != context.target }
            guard observation.isCurrent(context), selected == context.target else { return }
            if waitForOthers, !others.isEmpty { beginWaitingForOtherSessions() }
            else { beginCountdown(context: context) }
        }
    }

    private func handleNonTargetEvent(context: ObservationToken) async {
        guard waitingAfterTargetStop || (waitForOthers && countdownTask != nil) else { return }
        let active = await registry.runningSessions().filter { $0.id != context.target }
        guard observation.isCurrent(context), selected == context.target else { return }

        if waitingAfterTargetStop {
            if active.isEmpty {
                waitingAfterTargetStop = false
                beginCountdown(context: context)
            }
        } else if waitForOthers, countdownTask != nil, !active.isEmpty {
            beginWaitingForOtherSessions()
        }
    }

    private func beginWaitingForOtherSessions() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        waitingAfterTargetStop = true
        status = "目标已停止，等待其他会话"
    }

    private func cancelPendingSleep() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        waitingAfterTargetStop = false
    }

    private func beginCountdown(context: ObservationToken) {
        guard observation.isCurrent(context), selected == context.target else { return }
        countdownTask?.cancel()
        settings.delaySeconds = delaySeconds; settings.waitForOtherSessions = waitForOthers; settings.keepDisplayAwake = keepDisplayAwake
        let delay = delaySeconds
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for await value in SleepCountdownController.ticks(seconds: delay) {
                guard !Task.isCancelled, observation.isCurrent(context), selected == context.target else { return }
                countdown = value; status = "将在 \(value) 秒后休眠"
            }
            guard !Task.isCancelled, observation.isCurrent(context), selected == context.target else { return }
            power.stop(); sleepNow()
        }
    }
}

private struct LoggingSleeper: SystemSleeping {
    func sleepNow() throws { print("Codex Sleep Watcher: sleep requested") }
}
