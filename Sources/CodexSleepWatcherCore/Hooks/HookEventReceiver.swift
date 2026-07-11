import Foundation

public final class HookEventReceiver: @unchecked Sendable {
    public static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexSleepWatcher/events.sock").path
    }
    private var receiver: UnixDatagramReceiver?
    public init() {}
    public func events() throws -> AsyncStream<HookEvent> {
        let path = Self.defaultSocketPath
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let socket = try UnixDatagramReceiver(path: path); receiver = socket
        return AsyncStream { continuation in
            let task = Task.detached {
                while !Task.isCancelled {
                    guard let data = try? socket.receive(), let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in socket.close(); task.cancel() }
        }
    }
    public func stop() { receiver?.close(); receiver = nil }
}
