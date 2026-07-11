import Foundation
import IOKit.pwr_mgt

public final class PowerAssertionController: @unchecked Sendable {
    private var ids: [IOPMAssertionID] = []
    public init() {}
    public func start(keepDisplayAwake: Bool) throws {
        stop()
        try create(kIOPMAssertionTypePreventUserIdleSystemSleep as String)
        if keepDisplayAwake { try create(kIOPMAssertionTypePreventUserIdleDisplaySleep as String) }
    }
    private func create(_ type: String) throws {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Monitoring selected Codex session" as CFString, &id)
        guard result == kIOReturnSuccess else { stop(); throw PowerError.assertion(result) }
        ids.append(id)
    }
    public func stop() { ids.forEach { IOPMAssertionRelease($0) }; ids.removeAll() }
    deinit { stop() }
}

public enum PowerError: Error { case assertion(IOReturn); case sleep(IOReturn) }
