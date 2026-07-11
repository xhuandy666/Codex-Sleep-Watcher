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
    static func main() throws {
        try onlyTargetStopStartsCountdown()
        try targetRestartCancelsCountdown()
        try waitForOthersDefersCountdown()
        try observationErrorsFailSafe()
        try appServerDecoding()
        print("PASS: 5 core tests")
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
}
