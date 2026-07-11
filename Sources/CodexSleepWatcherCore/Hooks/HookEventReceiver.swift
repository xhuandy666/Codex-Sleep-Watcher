import Foundation

public final class HookEventReceiver: @unchecked Sendable {
    public static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexSleepWatcher/events.sock").path
    }
    private let socketPath: String
    private var receiver: UnixDatagramReceiver?
    public init(socketPath: String = HookEventReceiver.defaultSocketPath) { self.socketPath = socketPath }
    public func events() throws -> AsyncStream<HookEvent> {
        let path = socketPath
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let socket = try UnixDatagramReceiver(path: path); receiver = socket
        return AsyncStream { continuation in
            let task = Task.detached {
                while !Task.isCancelled {
                    guard let data = try? socket.receive() else { break }
                    guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
#if DEBUG
                        print("CSW_EVENT ignored malformed datagram bytes=\(data.count)")
#endif
                        continue
                    }
#if DEBUG
                    print("CSW_EVENT received kind=\(event.kind.rawValue) id=\(event.sessionID.short)")
#endif
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in socket.close(); task.cancel() }
        }
    }
    public func stop() { receiver?.close(); receiver = nil }
}
