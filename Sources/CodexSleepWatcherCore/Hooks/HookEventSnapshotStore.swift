import Foundation
import Darwin

public struct HookEventSnapshotStore: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexSleepWatcher/session-state", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = HookEventSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    public func record(_ event: HookEvent) throws {
        try withLock(exclusive: true) {
            let destination = fileURL(for: event.sessionID)
            if let data = try? Data(contentsOf: destination),
               let existing = try? JSONDecoder().decode(HookEvent.self, from: data),
               existing.receivedAt >= event.receivedAt {
                return
            }
            try writeAtomically(JSONEncoder().encode(event), to: destination)
        }
    }

    public func latestEvents() throws -> [HookEvent] {
        try withLock(exclusive: false) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            var events: [HookEvent] = []
            for url in urls {
                guard url.pathExtension == "json",
                      let data = try? Data(contentsOf: url),
                      let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { continue }
                events.append(event)
            }
            return events.sorted { $0.receivedAt < $1.receivedAt }
        }
    }

    public func pruneCompletedEvents(before cutoff: Date) throws {
        try withLock(exclusive: true) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let event = try? JSONDecoder().decode(HookEvent.self, from: data),
                      event.kind == .stop,
                      event.receivedAt < cutoff else { continue }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func fileURL(for sessionID: SessionID) -> URL {
        let encoded = Data(sessionID.rawValue.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent(encoded).appendingPathExtension("json")
    }

    private func withLock<T>(exclusive: Bool, _ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard chmod(directory.path, S_IRWXU) == 0 else { throw posixError() }
        let lockURL = directory.appendingPathComponent(".lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw posixError() }
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw CocoaError(.fileLocking)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_CREAT | O_EXCL | O_WRONLY,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw posixError() }
        var removeTemporary = true
        defer {
            Darwin.close(descriptor)
            if removeTemporary { Darwin.unlink(temporary.path) }
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw posixError() }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw posixError() }
        removeTemporary = false
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
