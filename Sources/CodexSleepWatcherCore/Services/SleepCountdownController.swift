import Foundation

public enum SleepCountdownController {
    public static func ticks(seconds: Int) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task {
                for value in stride(from: max(0, seconds), through: 0, by: -1) {
                    if Task.isCancelled { break }
                    continuation.yield(value)
                    if value > 0 { try? await Task.sleep(for: .seconds(1)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
