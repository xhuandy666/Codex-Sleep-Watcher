import Foundation

public actor SessionRegistry {
    private struct Entry { var summary: SessionSummary; var lastEventAt: Date }
    private var entries: [SessionID: Entry] = [:]
    public init() {}

    public func refresh(from summaries: [SessionSummary]) {
        for summary in summaries {
            guard entries[summary.id]?.lastEventAt ?? .distantPast <= summary.updatedAt else { continue }
            entries[summary.id] = Entry(summary: summary, lastEventAt: summary.updatedAt)
        }
    }

    public func apply(_ event: HookEvent) {
        guard entries[event.sessionID]?.lastEventAt ?? .distantPast <= event.receivedAt else { return }
        var summary = entries[event.sessionID]?.summary ?? SessionSummary(
            id: event.sessionID, threadID: event.sessionID.rawValue, name: URL(fileURLWithPath: event.cwd).lastPathComponent,
            cwd: event.cwd, updatedAt: event.receivedAt, status: .idle)
        switch event.kind {
        case .userPromptSubmit: summary.status = .running(turnID: event.turnID)
        case .permissionRequest: summary.status = .waitingOnApproval
        case .stop, .sessionStart: summary.status = .idle
        }
        summary.updatedAt = event.receivedAt
        entries[event.sessionID] = Entry(summary: summary, lastEventAt: event.receivedAt)
    }

    public func session(id: SessionID) -> SessionSummary? { entries[id]?.summary }
    public func runningSessions() -> [SessionSummary] { entries.values.map(\.summary).filter { $0.status.isRunning } }
}
