import Foundation

public struct SessionID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public var short: String { String(rawValue.prefix(8)) }
}

public struct TurnID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum SessionStatus: Equatable, Sendable {
    case running(turnID: TurnID?)
    case waitingOnApproval
    case waitingOnUserInput
    case idle
    case unknown

    public var isRunning: Bool {
        switch self {
        case .running: true
        default: false
        }
    }
}

public struct SessionSummary: Identifiable, Equatable, Sendable {
    public var id: SessionID
    public var threadID: String
    public var name: String
    public var cwd: String
    public var updatedAt: Date
    public var status: SessionStatus

    public init(id: SessionID, threadID: String, name: String, cwd: String, updatedAt: Date, status: SessionStatus) {
        self.id = id
        self.threadID = threadID
        self.name = name
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.status = status
    }
}

public struct WatchSettings: Equatable, Sendable {
    public var delaySeconds: Int
    public var waitForOtherSessions: Bool
    public init(delaySeconds: Int = 30, waitForOtherSessions: Bool = false) {
        self.delaySeconds = max(0, min(delaySeconds, 300))
        self.waitForOtherSessions = waitForOtherSessions
    }
}

public enum WatchPhase: Equatable, Sendable {
    case setupRequired(String)
    case idle
    case monitoring(SessionID)
    case waitingForOtherSessions(SessionID)
    case countdown(SessionID, secondsRemaining: Int)
    case sleeping(SessionID)
}

public enum WatchEvent: Equatable, Sendable {
    case setupFailed(String)
    case setupReady
    case knownRunningSessions(Set<SessionID>)
    case selectTarget(SessionID)
    case sessionEvent(sessionID: SessionID, status: SessionStatus)
    case countdownTick
    case cancel
    case fatalObservationError(String)
}

public enum WatchStateError: Error, Equatable {
    case targetIsNotRunning(SessionID)
}
