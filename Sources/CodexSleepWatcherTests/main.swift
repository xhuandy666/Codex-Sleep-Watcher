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
        try appServerDecoding()
        try hookEventPrivacyAndSocketRoundTrip()
        try hookInstallerPreservesExistingEntries()
        try await sessionRegistryReconcilesEvents()
        print("PASS: 8 core tests")
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

    static func appServerDecoding() throws {
        let json = #"{"data":[{"id":"thread-a","sessionId":"session-a","name":"Build app","cwd":"/repo/a","createdAt":1,"updatedAt":2,"status":{"type":"active","activeFlags":[]},"source":"appServer","modelProvider":"openai","cliVersion":"1","ephemeral":false,"turns":[],"preview":"ignored"}],"nextCursor":null}"#
        let response = try JSONDecoder().decode(ThreadListResponse.self, from: Data(json.utf8))
        let sessions = SessionDiscoveryService.mapActiveThreads(response.data)
        try expect(sessions.first?.id == SessionID("session-a"), "thread/list did not map sessionId")
        try expect(sessions.first?.name == "Build app", "thread/list lost display name")
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
        try expect(text.components(separatedBy: ownerField).count - 1 == 4, "installer did not create exactly four owned hooks")
        try installer.uninstall()
        let uninstalled = try String(contentsOf: file, encoding: .utf8)
        try expect(uninstalled.contains("/existing") && !uninstalled.contains(HookInstaller.owner), "uninstall removed unrelated hooks")
    }

    static func sessionRegistryReconcilesEvents() async throws {
        let registry = SessionRegistry()
        let summary = SessionSummary(id: SessionID("s1"), threadID: "thread-1", name: "Task", cwd: "/repo", updatedAt: Date(timeIntervalSince1970: 10), status: .running(turnID: nil))
        await registry.refresh(from: [summary])
        await registry.apply(HookEvent(kind: .stop, sessionID: SessionID("s1"), turnID: TurnID("t1"), cwd: "/repo", receivedAt: Date(timeIntervalSince1970: 20)))
        let status = await registry.session(id: SessionID("s1"))?.status
        try expect(status == .idle, "newer Stop event did not override snapshot")
    }
}
