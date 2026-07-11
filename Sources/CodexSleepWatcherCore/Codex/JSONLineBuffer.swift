import Foundation

public struct JSONLineBuffer: Sendable {
    private var storage = Data()

    public init() {}

    public mutating func append<D: DataProtocol>(_ data: D) {
        storage.append(contentsOf: data)
    }

    public mutating func nextLine() -> Data? {
        guard let newline = storage.firstIndex(of: 0x0A) else { return nil }
        let line = Data(storage[..<newline])
        storage.removeSubrange(...newline)
        return line
    }
}
