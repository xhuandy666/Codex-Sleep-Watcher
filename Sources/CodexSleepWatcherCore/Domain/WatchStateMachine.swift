public struct WatchStateMachine: Sendable {
    public private(set) var phase: WatchPhase
    public private(set) var lastError: String?
    public var settings: WatchSettings

    private var activeSessions: Set<SessionID> = []
    private var target: SessionID?

    public init(settings: WatchSettings = .init(), phase: WatchPhase = .idle) {
        self.settings = settings
        self.phase = phase
    }

    public mutating func reduce(_ event: WatchEvent) throws {
        switch event {
        case .setupFailed(let message):
            reset(to: .setupRequired(message), error: message)
        case .setupReady:
            reset(to: .idle)
        case .knownRunningSessions(let sessions):
            activeSessions = sessions
        case .selectTarget(let sessionID):
            guard activeSessions.contains(sessionID) else { throw WatchStateError.targetIsNotRunning(sessionID) }
            target = sessionID
            lastError = nil
            phase = .monitoring(sessionID)
        case .sessionEvent(let sessionID, let status):
            applyStatus(status, to: sessionID)
        case .countdownTick:
            tickCountdown()
        case .cancel:
            reset(to: .idle)
        case .fatalObservationError(let message):
            reset(to: .idle, error: message)
        }
    }

    private mutating func applyStatus(_ status: SessionStatus, to sessionID: SessionID) {
        if status.isLive {
            activeSessions.insert(sessionID)
        } else {
            activeSessions.remove(sessionID)
        }

        guard sessionID == target else {
            if settings.waitForOtherSessions, status.isLive, case .countdown(let targetID, _) = phase {
                phase = .waitingForOtherSessions(targetID)
            } else if case .waitingForOtherSessions(let targetID) = phase, activeSessions.isEmpty {
                phase = .countdown(targetID, secondsRemaining: settings.delaySeconds)
            }
            return
        }

        if status.isLive {
            phase = .monitoring(sessionID)
        } else if settings.waitForOtherSessions, !activeSessions.isEmpty {
            phase = .waitingForOtherSessions(sessionID)
        } else {
            phase = .countdown(sessionID, secondsRemaining: settings.delaySeconds)
        }
    }

    private mutating func tickCountdown() {
        guard case .countdown(let sessionID, let remaining) = phase else { return }
        phase = remaining > 0
            ? .countdown(sessionID, secondsRemaining: remaining - 1)
            : .sleeping(sessionID)
    }

    private mutating func reset(to newPhase: WatchPhase, error: String? = nil) {
        target = nil
        phase = newPhase
        lastError = error
    }
}
