import Foundation

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var delaySeconds: Int {
        get { defaults.object(forKey: "delaySeconds") == nil ? 30 : max(0, min(defaults.integer(forKey: "delaySeconds"), 300)) }
        set { defaults.set(max(0, min(newValue, 300)), forKey: "delaySeconds") }
    }
    public var waitForOtherSessions: Bool { get { defaults.bool(forKey: "waitForOtherSessions") } set { defaults.set(newValue, forKey: "waitForOtherSessions") } }
    public var keepDisplayAwake: Bool { get { defaults.bool(forKey: "keepDisplayAwake") } set { defaults.set(newValue, forKey: "keepDisplayAwake") } }
}
