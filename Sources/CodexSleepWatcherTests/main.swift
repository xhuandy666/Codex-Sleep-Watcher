import Foundation
import CodexSleepWatcherCore

enum TestFailure: Error, CustomStringConvertible {
    case expected(String)
    var description: String {
        switch self { case .expected(let message): return message }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.expected(message) }
}

@main
struct CoreTestRunner {
    static func main() async throws {
        try onlyTargetStopStartsCountdown()
        try targetRestartCancelsCountdown()
        try waitForOthersDefersCountdown()
        try observationErrorsFailSafe()
        try recentSessionDiscoveryIncludesUnloadedThreads()
        try sessionStatusLabels()
        try hookEventPrivacyAndSocketRoundTrip()
        try hookInstallerPreservesExistingEntries()
        try await sessionRegistryReconcilesEvents()
        try await sessionRegistryPreservesSelectedSession()
        try welcomePreferencePersists()
        try hookHelperLocatorSupportsAppAndDebugLayouts()
        try jsonLineBufferPreservesFragmentedResponses()
        try await registryPreservesHookOnlyRunningSession()
        try await sessionStartMarksSessionRunning()
        try await hookReceiverSkipsMalformedDatagrams()
        try concurrentSessionShortIDsAreDistinct()
        try codexLocatorSupportsFinderEnvironment()
        try await toolHooksRestoreRunningState()
        try targetEventDecisionIsPermissionSafe()
        try permissionWaitDoesNotStartCountdown()
        try permissionCancelsPendingSleep()
        try waitingOtherSessionDefersCountdown()
        try await registryTreatsWaitingSessionsAsActive()
        try await registryRejectsStaleStop()
        try newOtherActivityInterruptsCountdown()
        try observationFenceRejectsStaleWork()
        print("PASS: 27 core tests")
    }

    static let target = SessionID("target")
    static let other = SessionID("other")

    static func onlyTargetStopStartsCountdown() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.knownRunningSessions([target, other]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: other, status: .idle))
        try expect(machine.phase == .monitoring(target), "non-target stop changed phase")
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try expect(machine.phase == .countdown(target, secondsRemaining: 30), "target stop did not start countdown")
    }

    static func targetRestartCancelsCountdown() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.knownRunningSessions([target]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try machine.reduce(.sessionEvent(sessionID: target, status: .running(turnID: TurnID("turn-2"))))
        try expect(machine.phase == .monitoring(target), "target restart did not cancel countdown")
    }

    static func waitForOthersDefersCountdown() throws {
        var machine = WatchStateMachine(settings: .init(delaySeconds: 30, waitForOtherSessions: true))
        try machine.reduce(.knownRunningSessions([target, other]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try expect(machine.phase == .waitingForOtherSessions(target), "target stop did not wait for other sessions")
        try machine.reduce(.sessionEvent(sessionID: other, status: .idle))
        try expect(machine.phase == .countdown(target, secondsRemaining: 30), "last other session did not start countdown")
    }

    static func observationErrorsFailSafe() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.knownRunningSessions([target]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.fatalObservationError("event stream disconnected"))
        try expect(machine.phase == .idle, "observation error did not return to idle")
        try expect(machine.lastError == "event stream disconnected", "observation error was not retained")
    }

    static func recentSessionDiscoveryIncludesUnloadedThreads() throws {
        let json = #"{"data":[{"id":"thread-a","sessionId":"session-a","name":"Build app","cwd":"/repo/a","updatedAt":2,"status":{"type":"active","activeFlags":[]}},{"id":"thread-b","sessionId":"session-b","name":"Review app","cwd":"/repo/b","updatedAt":3,"status":{"type":"notLoaded"}},{"id":"thread-c","sessionId":"session-c","name":"Idle app","cwd":"/repo/c","updatedAt":1,"status":{"type":"idle"}}],"nextCursor":null}"#
        let response = try JSONDecoder().decode(ThreadListResponse.self, from: Data(json.utf8))
        let sessions = SessionDiscoveryService.mapRecentThreads(response.data, limit: 2)
        try expect(sessions.map(\.id) == [SessionID("session-b"), SessionID("session-a")], "recent thread mapping filtered or misordered candidates")
        try expect(sessions.first?.status == .unknown, "notLoaded thread did not map to unknown status")
    }

    static func sessionStatusLabels() throws {
        try expect(SessionStatus.running(turnID: nil).displayName == "运行中", "running label is unclear")
        try expect(SessionStatus.waitingOnApproval.displayName == "等待授权", "approval label is unclear")
        try expect(SessionStatus.waitingOnUserInput.displayName == "等待输入", "input label is unclear")
        try expect(SessionStatus.idle.displayName == "本轮已完成", "idle label is unclear")
        try expect(SessionStatus.unknown.displayName == "尚未收到事件", "unknown label is unclear")
    }

    static func hookEventPrivacyAndSocketRoundTrip() throws {
        let input = Data(#"{"session_id":"s1","turn_id":"t1","cwd":"/repo","hook_event_name":"Stop","prompt":"secret","last_assistant_message":"secret"}"#.utf8)
        let event = try HookEvent.fromHookInput(input, receivedAt: Date(timeIntervalSince1970: 10))
        let encoded = try JSONEncoder().encode(event)
        try expect(!String(decoding: encoded, as: UTF8.self).contains("secret"), "hook event leaked task content")
        let path = NSTemporaryDirectory() + "/csw-\(UUID().uuidString.prefix(8)).sock"
        let receiver = try UnixDatagramReceiver(path: path)
        defer { receiver.close() }
        try UnixDatagramSocket.send(encoded, to: path)
        let received = try receiver.receive()
        let decoded = try JSONDecoder().decode(HookEvent.self, from: received)
        try expect(decoded == event, "socket changed hook event")
    }

    static func hookInstallerPreservesExistingEntries() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("hooks.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/existing","statusMessage":"Existing"}]}]}}"#.utf8).write(to: file)
        let installer = HookInstaller(hooksFile: file)
        try installer.install(helperPath: "/Applications/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook")
        try installer.install(helperPath: "/Applications/Codex Sleep Watcher.app/Contents/Helpers/codex-sleep-hook")
        let text = try String(contentsOf: file, encoding: .utf8)
        try expect(text.contains("/existing"), "installer removed an existing hook")
        let ownerField = #""statusMessage" : "Codex Sleep Watcher""#
        try expect(text.components(separatedBy: ownerField).count - 1 == 6, "installer did not create exactly six owned hooks")
        try installer.uninstall()
        let uninstalled = try String(contentsOf: file, encoding: .utf8)
        try expect(uninstalled.contains("/existing") && !uninstalled.contains(HookInstaller.owner), "uninstall removed unrelated hooks")
    }

    static func sessionRegistryReconcilesEvents() async throws {
        let registry = SessionRegistry()
        let summary = SessionSummary(id: SessionID("s1"), threadID: "thread-1", name: "Task", cwd: "/repo", updatedAt: Date(timeIntervalSince1970: 10), status: .running(turnID: nil))
        await registry.refresh(from: [summary])
        await registry.apply(HookEvent(kind: .stop, sessionID: SessionID("s1"), turnID: TurnID("t1"), cwd: "/repo", receivedAt: Date(timeIntervalSince1970: 20)))
        await registry.refresh(from: [summary])
        let status = await registry.session(id: SessionID("s1"))?.status
        try expect(status == .idle, "newer Stop event did not override snapshot")
    }

    static func sessionRegistryPreservesSelectedSession() async throws {
        let registry = SessionRegistry()
        let selected = SessionSummary(id: SessionID("selected"), threadID: "selected", name: "Selected", cwd: "/selected", updatedAt: Date(timeIntervalSince1970: 1), status: .unknown)
        await registry.refresh(from: [selected], preserving: nil)
        let recent = SessionSummary(id: SessionID("recent"), threadID: "recent", name: "Recent", cwd: "/recent", updatedAt: Date(timeIntervalSince1970: 2), status: .unknown)
        await registry.refresh(from: [recent], preserving: selected.id)
        let sessions = await registry.sessions()
        try expect(sessions.map(\.id).contains(selected.id), "refresh removed the selected session")
    }

    static func welcomePreferencePersists() throws {
        let suite = "CodexSleepWatcherTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw TestFailure.expected("could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        try expect(!first.hasShownWelcome, "welcome should not be marked shown initially")
        first.hasShownWelcome = true
        let second = SettingsStore(defaults: defaults)
        try expect(second.hasShownWelcome, "welcome preference did not persist")
    }

    static func hookHelperLocatorSupportsAppAndDebugLayouts() throws {
        let app = URL(fileURLWithPath: "/Applications/Codex Sleep Watcher.app")
        let executable = URL(fileURLWithPath: "/tmp/debug/CodexSleepWatcherApp")
        let packaged = app.appendingPathComponent("Contents/Helpers/codex-sleep-hook").path
        let debug = executable.deletingLastPathComponent().appendingPathComponent("codex-sleep-hook").path
        let packagedResult = HookHelperLocator.locate(bundleURL: app, executableURL: executable) { $0 == packaged }
        try expect(packagedResult?.path == packaged, "locator did not prefer packaged helper")
        let debugResult = HookHelperLocator.locate(bundleURL: app, executableURL: executable) { $0 == debug }
        try expect(debugResult?.path == debug, "locator did not find debug sibling helper")
    }

    static func jsonLineBufferPreservesFragmentedResponses() throws {
        var buffer = JSONLineBuffer()
        let response = Data(#"{"id":1,"result":{"data":[1,2,3]}}"#.utf8)
        buffer.append(response.prefix(12))
        try expect(buffer.nextLine() == nil, "buffer emitted an incomplete JSON line")
        buffer.append(response.dropFirst(12))
        try expect(buffer.nextLine() == nil, "buffer emitted JSON before newline")
        buffer.append(Data("\n{\"id\":2}\n".utf8))
        try expect(buffer.nextLine() == response, "buffer lost the fragmented response")
        try expect(String(decoding: buffer.nextLine() ?? Data(), as: UTF8.self) == #"{"id":2}"#, "buffer lost a trailing complete response")
    }

    static func registryPreservesHookOnlyRunningSession() async throws {
        let registry = SessionRegistry()
        let event = HookEvent(kind: .userPromptSubmit, sessionID: SessionID("hook-only"), turnID: TurnID("turn"), cwd: "/tmp/hook-only", receivedAt: Date())
        await registry.apply(event)
        await registry.refresh(from: [], preserving: nil)
        let sessions = await registry.sessions()
        try expect(sessions.first?.id == event.sessionID, "refresh removed a running session discovered only by Hooks")
        try expect(sessions.first?.status == .running(turnID: event.turnID), "refresh lost the Hook-derived running state")
    }

    static func sessionStartMarksSessionRunning() async throws {
        let registry = SessionRegistry()
        let event = HookEvent(kind: .sessionStart, sessionID: SessionID("started"), turnID: nil, cwd: "/tmp/started", receivedAt: Date())
        await registry.apply(event)
        let status = await registry.session(id: event.sessionID)?.status
        try expect(status == .running(turnID: nil), "SessionStart did not mark the session running")
    }

    static func hookReceiverSkipsMalformedDatagrams() async throws {
        let path = NSTemporaryDirectory() + "/csw-stream-\(UUID().uuidString.prefix(8)).sock"
        let receiver = HookEventReceiver(socketPath: path)
        let stream = try receiver.events()
        defer { receiver.stop() }
        try UnixDatagramSocket.send(Data("not-json".utf8), to: path)
        let event = HookEvent(kind: .userPromptSubmit, sessionID: SessionID("after-invalid"), turnID: nil, cwd: "/tmp", receivedAt: Date())
        try UnixDatagramSocket.send(JSONEncoder().encode(event), to: path)
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        try expect(received == event, "receiver stopped after a malformed datagram")
    }

    static func concurrentSessionShortIDsAreDistinct() throws {
        let first = SessionID("019f521b-9a08-7560-9457-f6c6559709ff")
        let second = SessionID("019f521b-fedd-78b0-b927-a179e0fa6ef0")
        try expect(first.short != second.short, "concurrent UUIDv7 sessions have colliding short IDs")
    }

    static func codexLocatorSupportsFinderEnvironment() throws {
        let chatGPTCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let result = CodexExecutableLocator.locate(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { $0 == chatGPTCodex }
        try expect(result?.path == chatGPTCodex, "Finder environment could not locate the Codex bundled with ChatGPT")
    }

    static func toolHooksRestoreRunningState() async throws {
        let preInput = Data(#"{"session_id":"tool-session","turn_id":"turn-1","cwd":"/repo","hook_event_name":"PreToolUse"}"#.utf8)
        let postInput = Data(#"{"session_id":"tool-session","turn_id":"turn-1","cwd":"/repo","hook_event_name":"PostToolUse"}"#.utf8)
        let pre = try HookEvent.fromHookInput(preInput, receivedAt: Date(timeIntervalSince1970: 20))
        let post = try HookEvent.fromHookInput(postInput, receivedAt: Date(timeIntervalSince1970: 30))
        try expect(pre.kind == .preToolUse, "PreToolUse did not decode")
        try expect(post.kind == .postToolUse, "PostToolUse did not decode")

        let registry = SessionRegistry()
        await registry.apply(HookEvent(kind: .permissionRequest, sessionID: pre.sessionID, turnID: pre.turnID, cwd: pre.cwd, receivedAt: Date(timeIntervalSince1970: 10)))
        await registry.apply(pre)
        let preStatus = await registry.session(id: pre.sessionID)?.status
        try expect(preStatus == .running(turnID: pre.turnID), "PreToolUse did not restore running state")
        await registry.apply(HookEvent(kind: .permissionRequest, sessionID: post.sessionID, turnID: post.turnID, cwd: post.cwd, receivedAt: Date(timeIntervalSince1970: 25)))
        await registry.apply(post)
        let postStatus = await registry.session(id: post.sessionID)?.status
        try expect(postStatus == .running(turnID: post.turnID), "PostToolUse did not restore running state")
    }

    static func targetEventDecisionIsPermissionSafe() throws {
        try expect(HookEventKind.sessionStart.targetDecision == .activity, "SessionStart is not activity")
        try expect(HookEventKind.userPromptSubmit.targetDecision == .activity, "UserPromptSubmit is not activity")
        try expect(HookEventKind.preToolUse.targetDecision == .activity, "PreToolUse is not activity")
        try expect(HookEventKind.postToolUse.targetDecision == .activity, "PostToolUse is not activity")
        try expect(HookEventKind.permissionRequest.targetDecision == .waitingForAuthorization, "PermissionRequest can trigger sleep")
        try expect(HookEventKind.stop.targetDecision == .stopped, "Stop is not classified as stopped")
    }

    static func permissionWaitDoesNotStartCountdown() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.knownRunningSessions([target]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .waitingOnApproval))
        try expect(machine.phase == .monitoring(target), "waiting for authorization started a countdown")
        try machine.reduce(.sessionEvent(sessionID: target, status: .waitingOnUserInput))
        try expect(machine.phase == .monitoring(target), "waiting for user input started a countdown")
    }

    static func permissionCancelsPendingSleep() throws {
        var machine = WatchStateMachine()
        try machine.reduce(.knownRunningSessions([target]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try expect(machine.phase == .countdown(target, secondsRemaining: 30), "Stop did not start the test countdown")
        try machine.reduce(.sessionEvent(sessionID: target, status: .waitingOnApproval))
        try expect(machine.phase == .monitoring(target), "authorization request did not cancel a pending countdown")
    }

    static func waitingOtherSessionDefersCountdown() throws {
        var machine = WatchStateMachine(settings: .init(delaySeconds: 30, waitForOtherSessions: true))
        try machine.reduce(.knownRunningSessions([target, other]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: other, status: .waitingOnApproval))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try expect(machine.phase == .waitingForOtherSessions(target), "waiting other session did not defer countdown")
    }

    static func registryTreatsWaitingSessionsAsActive() async throws {
        let registry = SessionRegistry()
        let event = HookEvent(
            kind: .permissionRequest,
            sessionID: SessionID("waiting"),
            turnID: TurnID("turn"),
            cwd: "/repo",
            receivedAt: Date()
        )
        await registry.apply(event)
        let active = await registry.runningSessions()
        try expect(active.map(\.id).contains(event.sessionID), "waiting authorization session was not considered active")

        let waitingInput = SessionSummary(
            id: SessionID("waiting-input"),
            threadID: "waiting-input",
            name: "Waiting input",
            cwd: "/repo",
            updatedAt: Date(),
            status: .waitingOnUserInput
        )
        await registry.refresh(from: [waitingInput])
        let refreshedActive = await registry.runningSessions()
        try expect(refreshedActive.map(\.id).contains(waitingInput.id), "waiting input session was not considered active")
    }

    static func registryRejectsStaleStop() async throws {
        let registry = SessionRegistry()
        let sessionID = SessionID("ordered")
        let activity = HookEvent(
            kind: .preToolUse,
            sessionID: sessionID,
            turnID: TurnID("turn"),
            cwd: "/repo",
            receivedAt: Date(timeIntervalSince1970: 20)
        )
        let staleStop = HookEvent(
            kind: .stop,
            sessionID: sessionID,
            turnID: TurnID("turn"),
            cwd: "/repo",
            receivedAt: Date(timeIntervalSince1970: 10)
        )
        let activityAccepted = await registry.apply(activity)
        let staleStopAccepted = await registry.apply(staleStop)
        try expect(activityAccepted, "new activity event was rejected")
        try expect(!staleStopAccepted, "stale Stop event was accepted")
        let status = await registry.session(id: sessionID)?.status
        try expect(status == .running(turnID: activity.turnID), "stale Stop changed the running state")
    }

    static func newOtherActivityInterruptsCountdown() throws {
        var machine = WatchStateMachine(settings: .init(delaySeconds: 30, waitForOtherSessions: true))
        try machine.reduce(.knownRunningSessions([target]))
        try machine.reduce(.selectTarget(target))
        try machine.reduce(.sessionEvent(sessionID: target, status: .idle))
        try expect(machine.phase == .countdown(target, secondsRemaining: 30), "target Stop did not start countdown")
        try machine.reduce(.sessionEvent(sessionID: other, status: .waitingOnApproval))
        try expect(machine.phase == .waitingForOtherSessions(target), "new active session did not interrupt countdown")
    }

    static func observationFenceRejectsStaleWork() throws {
        var fence = ObservationFence()
        let first = fence.select(target)
        try expect(fence.isCurrent(first), "new observation token was not current")
        fence.cancel()
        try expect(!fence.isCurrent(first), "cancel did not invalidate pending observation work")
        let second = fence.select(other)
        try expect(!fence.isCurrent(first), "retargeting revalidated the old observation token")
        try expect(fence.isCurrent(second), "retargeted observation token was not current")
    }
}
