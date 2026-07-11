import Foundation

public struct ThreadListResponse: Decodable, Sendable {
    public let data: [ThreadRecord]
    public let nextCursor: String?
}

public struct ThreadRecord: Decodable, Sendable {
    public let id: String
    public let sessionId: String
    public let name: String?
    public let cwd: String
    public let updatedAt: Int64
    public let status: ThreadRuntimeStatus
}

public enum ThreadRuntimeStatus: Decodable, Sendable {
    case active([String]), idle, notLoaded, systemError
    enum Keys: String, CodingKey { case type, activeFlags }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "active": self = .active(try c.decodeIfPresent([String].self, forKey: .activeFlags) ?? [])
        case "idle": self = .idle
        case "notLoaded": self = .notLoaded
        default: self = .systemError
        }
    }
}
