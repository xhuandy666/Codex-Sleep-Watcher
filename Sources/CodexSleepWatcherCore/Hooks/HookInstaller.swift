import Foundation

public struct HookInstaller: Sendable {
    public static let owner = "Codex Sleep Watcher"
    public let hooksFile: URL
    private let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]

    public init(hooksFile: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")) {
        self.hooksFile = hooksFile
    }

    public func install(helperPath: String) throws {
        var root = try load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        removeOwned(from: &hooks)
        let command = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 5, "statusMessage": Self.owner]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try save(root)
    }

    public func uninstall() throws {
        var root = try load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        removeOwned(from: &hooks)
        root["hooks"] = hooks
        try save(root)
    }

    private func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksFile.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile))
        guard let root = object as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return root
    }

    private func save(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: hooksFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksFile, options: .atomic)
        chmod(hooksFile.path, S_IRUSR | S_IWUSR)
    }

    private func removeOwned(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            hooks[event] = groups.compactMap { group in
                guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
                handlers.removeAll { $0["statusMessage"] as? String == Self.owner }
                guard !handlers.isEmpty else { return nil }
                var copy = group; copy["hooks"] = handlers; return copy
            }
        }
    }
}
