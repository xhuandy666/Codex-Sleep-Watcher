import Foundation

public actor SessionRegistry {
    private struct Entry { var summary: SessionSummary; var lastHookEventAt: Date? }
    private var entries: [SessionID: Entry] = [:]
    public init() {}

    public func refresh(from summaries: [SessionSummary], preserving selected: SessionID? = nil) {
        let hookDiscovered = entries.values.compactMap { $0.summary.status.isLive ? $0.summary.id : nil }
        let visible = Set(summaries.map(\.id))
            .union(selected.map { [$0] } ?? [])
            .union(hookDiscovered)
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

    @discardableResult
    public func apply(_ event: HookEvent) -> Bool {
        guard entries[event.sessionID]?.lastHookEventAt ?? .distantPast < event.receivedAt else { return false }
        var summary = entries[event.sessionID]?.summary ?? SessionSummary(
            id: event.sessionID, threadID: event.sessionID.rawValue, name: URL(fileURLWithPath: event.cwd).lastPathComponent,
            cwd: event.cwd, updatedAt: event.receivedAt, status: .idle)
        switch event.kind {
        case .sessionStart: summary.status = .running(turnID: nil)
        case .userPromptSubmit, .preToolUse, .postToolUse: summary.status = .running(turnID: event.turnID)
        case .permissionRequest: summary.status = .waitingOnApproval
        case .stop: summary.status = .idle
        }
        summary.updatedAt = event.receivedAt
        entries[event.sessionID] = Entry(summary: summary, lastHookEventAt: event.receivedAt)
        return true
    }

    public func markStaleHookEvents(before cutoff: Date) {
        for id in Array(entries.keys) {
            guard var entry = entries[id],
                  let lastHookEventAt = entry.lastHookEventAt,
                  lastHookEventAt < cutoff else { continue }
            if entry.summary.status.isLive {
                entry.summary.status = .staleActive
            } else {
                entry.lastHookEventAt = nil
                entry.summary.status = .unknown
            }
            entries[id] = entry
        }
    }

    public func session(id: SessionID) -> SessionSummary? { entries[id]?.summary }
    public func sessions() -> [SessionSummary] { entries.values.map(\.summary).sorted { $0.updatedAt > $1.updatedAt } }
    public func runningSessions() -> [SessionSummary] { entries.values.map(\.summary).filter { $0.status.isLive } }
}
