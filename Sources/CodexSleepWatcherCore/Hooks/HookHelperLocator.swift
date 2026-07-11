import Foundation

public enum HookHelperLocator {
    public static func locate(
        bundleURL: URL,
        executableURL: URL?,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL? {
        let packaged = bundleURL.appendingPathComponent("Contents/Helpers/codex-sleep-hook")
        if isExecutable(packaged.path) { return packaged }
        if let executableURL {
            let debug = executableURL.deletingLastPathComponent().appendingPathComponent("codex-sleep-hook")
            if isExecutable(debug.path) { return debug }
        }
        return nil
    }
}
