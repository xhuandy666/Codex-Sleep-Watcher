import Foundation

public actor SessionRegistry {
    private struct Entry { var summary: SessionSummary; var lastHookEventAt: Date? }
    private var entries: [SessionID: Entry] = [:]
    public init() {}

    public func refresh(from summaries: [SessionSummary], preserving selected: SessionID? = nil) {
        let visible = Set(summaries.map(\.id)).union(selected.map { [$0] } ?? [])
        entries = entries.filter { visible.contains($0.key) }
        for summary in summaries {
            if var entry = entries[summary.id] {
                let hookStatus = entry.summary.status
                entry.summary = summary
                if entry.lastHookEventAt != nil { entry.summary.status = hookStatus }
                entries[summary.id] = entry
            } else {
                entries[summary.id] = Entry(summary: summary, lastHookEventAt: nil)
            }
        }
    }

    public func apply(_ event: HookEvent) {
        guard entries[event.sessionID]?.lastHookEventAt ?? .distantPast <= event.receivedAt else { return }
        var summary = entries[event.sessionID]?.summary ?? SessionSummary(
            id: event.sessionID, threadID: event.sessionID.rawValue, name: URL(fileURLWithPath: event.cwd).lastPathComponent,
            cwd: event.cwd, updatedAt: event.receivedAt, status: .idle)
        switch event.kind {
        case .userPromptSubmit: summary.status = .running(turnID: event.turnID)
        case .permissionRequest: summary.status = .waitingOnApproval
        case .stop, .sessionStart: summary.status = .idle
        }
        summary.updatedAt = event.receivedAt
        entries[event.sessionID] = Entry(summary: summary, lastHookEventAt: event.receivedAt)
    }

    public func session(id: SessionID) -> SessionSummary? { entries[id]?.summary }
    public func sessions() -> [SessionSummary] { entries.values.map(\.summary).sorted { $0.updatedAt > $1.updatedAt } }
    public func runningSessions() -> [SessionSummary] { entries.values.map(\.summary).filter { $0.status.isRunning } }
}
