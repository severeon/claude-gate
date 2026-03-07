import Foundation

struct HookOutput: Codable {
    let hookSpecificOutput: HookSpecificOutput

    struct HookSpecificOutput: Codable {
        let hookEventName: String
        let permissionDecision: String
        let permissionDecisionReason: String?
    }

    static func allow(reason: String? = nil) -> HookOutput {
        HookOutput(hookSpecificOutput: HookSpecificOutput(
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: reason
        ))
    }

    static func deny(reason: String) -> HookOutput {
        HookOutput(hookSpecificOutput: HookSpecificOutput(
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: reason
        ))
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Failed to encode decision\"}}"
        }
        return str
    }
}
