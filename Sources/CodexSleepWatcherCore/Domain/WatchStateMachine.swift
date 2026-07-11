public struct WatchStateMachine: Sendable {
    public private(set) var phase: WatchPhase
    public private(set) var lastError: String?
    public var settings: WatchSettings

    private var runningSessions: Set<SessionID> = []
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
            runningSessions = sessions
        case .selectTarget(let sessionID):
            guard runningSessions.contains(sessionID) else { throw WatchStateError.targetIsNotRunning(sessionID) }
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
        if status.isRunning {
            runningSessions.insert(sessionID)
        } else {
            runningSessions.remove(sessionID)
        }

        guard sessionID == target else {
            if case .waitingForOtherSessions(let targetID) = phase, runningSessions.isEmpty {
                phase = .countdown(targetID, secondsRemaining: settings.delaySeconds)
            }
            return
        }

        if status.isRunning {
            phase = .monitoring(sessionID)
        } else if settings.waitForOtherSessions, !runningSessions.isEmpty {
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
