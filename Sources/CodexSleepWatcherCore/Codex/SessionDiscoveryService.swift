import Foundation

public enum SessionDiscoveryService {
    public static func mapActiveThreads(_ threads: [ThreadRecord]) -> [SessionSummary] {
        threads.compactMap { thread in
            guard case .active(let flags) = thread.status else { return nil }
            let status: SessionStatus = flags.contains("waitingOnApproval") ? .waitingOnApproval
                : flags.contains("waitingOnUserInput") ? .waitingOnUserInput
                : .running(turnID: nil)
            return SessionSummary(
                id: SessionID(thread.sessionId), threadID: thread.id,
                name: thread.name ?? URL(fileURLWithPath: thread.cwd).lastPathComponent,
                cwd: thread.cwd, updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt)), status: status
            )
        }
    }
}
