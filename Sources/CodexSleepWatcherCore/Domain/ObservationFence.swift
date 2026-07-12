public struct ObservationToken: Equatable, Sendable {
    public let target: SessionID
    fileprivate let generation: UInt64

    fileprivate init(target: SessionID, generation: UInt64) {
        self.target = target
        self.generation = generation
    }
}

public struct ObservationFence: Sendable {
    public private(set) var target: SessionID?
    private var generation: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func select(_ target: SessionID) -> ObservationToken {
        generation &+= 1
        self.target = target
        return ObservationToken(target: target, generation: generation)
    }

    public mutating func cancel() {
        generation &+= 1
        target = nil
    }

    public var token: ObservationToken? {
        target.map { ObservationToken(target: $0, generation: generation) }
    }

    public func isCurrent(_ token: ObservationToken) -> Bool {
        target == token.target && generation == token.generation
    }
}
