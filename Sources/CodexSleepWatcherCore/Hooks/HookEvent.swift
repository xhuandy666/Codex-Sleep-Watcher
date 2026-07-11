import Foundation

public enum HookEventKind: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
}

public struct HookEvent: Codable, Equatable, Sendable {
    public let kind: HookEventKind
    public let sessionID: SessionID
    public let turnID: TurnID?
    public let cwd: String
    public let receivedAt: Date

    public init(kind: HookEventKind, sessionID: SessionID, turnID: TurnID?, cwd: String, receivedAt: Date) {
        self.kind = kind; self.sessionID = sessionID; self.turnID = turnID; self.cwd = cwd; self.receivedAt = receivedAt
    }

    public static func fromHookInput(_ data: Data, receivedAt: Date) throws -> HookEvent {
        let raw = try JSONDecoder().decode(RawHookInput.self, from: data)
        guard let kind = HookEventKind(rawValue: raw.hookEventName) else { throw HookEventError.unsupportedEvent }
        return HookEvent(kind: kind, sessionID: SessionID(raw.sessionID), turnID: raw.turnID.map { TurnID($0) }, cwd: raw.cwd, receivedAt: receivedAt)
    }
}

private struct RawHookInput: Decodable {
    let sessionID: String, turnID: String?, cwd: String, hookEventName: String
    enum CodingKeys: String, CodingKey { case sessionID = "session_id", turnID = "turn_id", cwd, hookEventName = "hook_event_name" }
}

public enum HookEventError: Error { case unsupportedEvent }
