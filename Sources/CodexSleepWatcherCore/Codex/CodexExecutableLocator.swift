import Foundation

public enum CodexExecutableLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL? {
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        let knownCandidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".codex/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        return (pathCandidates + knownCandidates).first { isExecutable($0.path) }
    }
}
