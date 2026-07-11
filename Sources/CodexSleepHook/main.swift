import Foundation
import CodexSleepWatcherCore

let input = FileHandle.standardInput.readDataToEndOfFile()
if let event = try? HookEvent.fromHookInput(input, receivedAt: .now),
   let payload = try? JSONEncoder().encode(event) {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexSleepWatcher", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try? UnixDatagramSocket.send(payload, to: base.appendingPathComponent("events.sock").path)
}
