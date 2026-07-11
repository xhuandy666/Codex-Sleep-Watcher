import Foundation

public enum SessionDiscoveryService {
    public static func mapRecentThreads(_ threads: [ThreadRecord], limit: Int = 20) -> [SessionSummary] {
        threads.map { thread in
            let status: SessionStatus
            switch thread.status {
            case .active(let flags):
                status = flags.contains("waitingOnApproval") ? .waitingOnApproval
                    : flags.contains("waitingOnUserInput") ? .waitingOnUserInput
                    : .running(turnID: nil)
            case .idle, .notLoaded, .systemError:
                status = .unknown
            }
            return SessionSummary(
                id: SessionID(thread.sessionId), threadID: thread.id,
                name: thread.name ?? URL(fileURLWithPath: thread.cwd).lastPathComponent,
                cwd: thread.cwd, updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt)), status: status
            )
        }.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
