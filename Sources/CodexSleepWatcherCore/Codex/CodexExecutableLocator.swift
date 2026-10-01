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
        let applicationsDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ]
        let bundledCandidates = applicationsDirectories.flatMap { directory in
            ["ChatGPT.app", "Codex.app"].flatMap { appName in
                let resources = directory.appendingPathComponent(appName + "/Contents/Resources")
                return [
                    resources.appendingPathComponent("codex-cli/CodexCLI.app/Contents/MacOS/codex"),
                    resources.appendingPathComponent("codex-cli/bin/codex"),
                    resources.appendingPathComponent("codex"),
                ]
            }
        }
        let fallbackCandidates = [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".codex/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        // Prefer the desktop's matching runtime over a stale standalone CLI on PATH.
        return (bundledCandidates + pathCandidates + fallbackCandidates).first { isExecutable($0.path) }
    }
}
