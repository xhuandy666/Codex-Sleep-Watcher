import IOKit.pwr_mgt

public protocol SystemSleeping: Sendable { func sleepNow() throws }

public struct MacSystemSleeper: SystemSleeping {
    public init() {}
    public func sleepNow() throws {
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else { throw PowerError.sleep(kIOReturnError) }
        defer { IOServiceClose(connection) }
        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else { throw PowerError.sleep(result) }
    }
}
