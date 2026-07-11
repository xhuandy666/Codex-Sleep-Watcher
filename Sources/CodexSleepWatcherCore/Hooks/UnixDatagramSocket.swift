import Foundation
import Darwin

public enum UnixDatagramError: Error { case pathTooLong, system(Int32) }

private func address(for path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count < capacity else { throw UnixDatagramError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
        raw.copyBytes(from: bytes)
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return address
}

public enum UnixDatagramSocket {
    public static func send(_ data: Data, to path: String) throws {
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw UnixDatagramError.system(errno) }
        defer { Darwin.close(fd) }
        var addr = try address(for: path)
        let result = data.withUnsafeBytes { payload in
            withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, payload.baseAddress, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard result >= 0 else { throw UnixDatagramError.system(errno) }
    }
}

public final class UnixDatagramReceiver: @unchecked Sendable {
    private var fd: Int32
    private let path: String
    public init(path: String) throws {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw UnixDatagramError.system(errno) }
        var addr = try address(for: path)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { let code = errno; Darwin.close(fd); throw UnixDatagramError.system(code) }
        chmod(path, S_IRUSR | S_IWUSR)
    }
    public func receive() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count >= 0 else { throw UnixDatagramError.system(errno) }
        return Data(buffer.prefix(count))
    }
    public func close() { if fd >= 0 { Darwin.close(fd); fd = -1; unlink(path) } }
    deinit { close() }
}
