import Foundation

public struct HookInput: Codable {
    public let sessionId: String?
    public let toolName: String
    public let toolInput: [String: AnyCodable]
    public let cwd: String?
    public let permissionMode: String?
    public let hookEventName: String?

    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case transcriptPath = "transcript_path"
    }

    public var command: String? {
        toolInput["command"]?.stringValue
    }

    public var filePath: String? {
        toolInput["file_path"]?.stringValue
    }

    /// Claude's description of what the command does (Bash tool_input.description)
    public var toolDescription: String? {
        toolInput["description"]?.stringValue
    }

    public var toolInputAsString: String {
        if let data = try? JSONEncoder().encode(toolInput),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    /// Whether this is an MCP (Model Context Protocol) tool call
    public var isMCPTool: Bool {
        toolName.hasPrefix("mcp__")
    }

    /// The MCP namespace (e.g., "obsidian" from "mcp__obsidian__write_note")
    public var mcpNamespace: String? {
        guard isMCPTool else { return nil }
        // mcp__obsidian__write_note → ["mcp", "obsidian", "write_note"]
        let segments = toolName.components(separatedBy: "__")
        guard segments.count >= 2 else { return nil }
        return segments[1]
    }

    /// The MCP action (e.g., "write_note" from "mcp__obsidian__write_note")
    public var mcpAction: String? {
        guard isMCPTool else { return nil }
        let segments = toolName.components(separatedBy: "__")
        guard segments.count >= 3 else { return nil }
        return segments[2...].joined(separator: "__")
    }

    /// Agent tool prompt (for Agent tool dispatches)
    public var agentPrompt: String? {
        toolInput["prompt"]?.stringValue
    }

    /// Agent tool subagent type
    public var agentType: String? {
        toolInput["subagent_type"]?.stringValue
    }

    /// Human-readable display summary for gate windows.
    /// Provides meaningful context instead of raw JSON for MCP/Agent tools.
    public var displaySummary: String {
        // Bash: show command
        if let cmd = command {
            return cmd
        }
        // Write/Edit: show file path
        if let path = filePath {
            return "\(toolName): \(path)"
        }
        // Agent tool: show type and prompt snippet
        if toolName == "Agent" {
            let type = agentType ?? "general"
            if let prompt = agentPrompt {
                let short = prompt.count > 120 ? String(prompt.prefix(117)) + "..." : prompt
                return "Agent (\(type)): \(short)"
            }
            return "Agent (\(type))"
        }
        // MCP tools: show namespace/action and key fields
        if isMCPTool {
            let namespace = mcpNamespace ?? "unknown"
            let action = mcpAction ?? toolName
            let keyFields = extractMCPKeyFields()
            if !keyFields.isEmpty {
                return "\(namespace)/\(action): \(keyFields)"
            }
            return "\(namespace)/\(action)"
        }
        // Fallback: tool name + truncated JSON
        let json = toolInputAsString
        if json.count > 150 {
            return "\(toolName): \(String(json.prefix(147)))..."
        }
        return json.isEmpty ? toolName : "\(toolName): \(json)"
    }

    /// Extract the most useful fields from MCP tool input for display
    private func extractMCPKeyFields() -> String {
        // Common MCP field names that carry meaningful content
        let keyNames = ["path", "url", "query", "note", "title", "name",
                        "content", "filename", "selector", "text", "message"]
        var parts: [String] = []
        for key in keyNames {
            if let val = toolInput[key]?.stringValue, !val.isEmpty {
                let short = val.count > 80 ? String(val.prefix(77)) + "..." : val
                parts.append("\(key)=\(short)")
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// Type-erased Codable wrapper for JSON values
public struct AnyCodable: Codable {
    public let value: Any

    public var stringValue: String? {
        value as? String
    }

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}
