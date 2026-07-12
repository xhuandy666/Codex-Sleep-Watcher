public enum TargetEventDecision: Equatable, Sendable {
    case activity
    case waitingForAuthorization
    case stopped
}

public extension HookEventKind {
    var targetDecision: TargetEventDecision {
        switch self {
        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse:
            .activity
        case .permissionRequest:
            .waitingForAuthorization
        case .stop:
            .stopped
        }
    }
}
