import XCTest
@testable import ClaudeGateCore

final class RuleEngineTests: XCTestCase {

    private func fixturePath(_ name: String) -> String {
        Bundle.module.path(forResource: name, ofType: "toml", inDirectory: "Fixtures")!
    }

    private func makeInput(tool: String, command: String? = nil, filePath: String? = nil, extraFields: [String: Any]? = nil) -> HookInput {
        var toolInput: [String: Any] = [:]
        if let command = command {
            toolInput["command"] = command
        }
        if let filePath = filePath {
            toolInput["file_path"] = filePath
        }
        if let extra = extraFields {
            for (key, value) in extra {
                toolInput[key] = value
            }
        }
        return try! JSONDecoder().decode(HookInput.self, from: JSONSerialization.data(withJSONObject: [
            "tool_name": tool,
            "tool_input": toolInput
        ]))
    }

    // MARK: - Rule Matching

    func testPassthroughForSafeCommand() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "ls -la")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    func testDenyForRmRf() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf /")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNotNil(rule)
        XCTAssertEqual(action, .deny)
        XCTAssertEqual(rule?.name, "Block: rm -rf /")
    }

    func testDenyForRmRfHome() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf ~/Documents")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    func testDenyForRmWithMultipleFlags() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf /etc/hosts")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    func testGateForForcePush() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "git push --force origin main")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: force push")
    }

    func testGateForNpmInstall() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "npm install lodash")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: npm install")
    }

    func testGateForYarnAdd() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "yarn add react")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
    }

    func testPassthroughForNormalGitPush() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "git push origin main")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    func testPassthroughForRmSafeFile() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm temp.txt")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - Path Pattern Matching

    func testGateForEnvFileWrite() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Write", filePath: "/project/.env")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: env files")
    }

    func testGateForSshConfigEdit() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Edit", filePath: "/Users/me/.ssh/config")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: ssh config")
    }

    func testPassthroughForNormalFileWrite() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Write", filePath: "/project/src/main.swift")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - First Match Wins

    func testFirstMatchWins() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        // rm -rf / matches the deny rule before any gate rule
        let input = makeInput(tool: "Bash", command: "rm -rf /")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    // MARK: - Unmatched Tool

    func testUnmatchedToolUsesDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "UnknownTool", command: "anything")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - Config Parsing

    func testDefaultTimeout() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertEqual(engine.timeout, 60)
        XCTAssertEqual(engine.timeoutAction, .deny)
    }

    func testCustomTimeout() throws {
        let engine = try RuleEngine(configPath: fixturePath("custom-timeout"))
        XCTAssertEqual(engine.timeout, 120)
        XCTAssertEqual(engine.timeoutAction, .passthrough)
    }

    func testTimeoutMinimumClamping() throws {
        let engine = try RuleEngine(configPath: fixturePath("low-timeout"))
        XCTAssertEqual(engine.timeout, 5, "Timeout should be clamped to minimum 5 seconds")
    }

    func testPassthroughTimeoutMinimumClamping() throws {
        let engine = try RuleEngine(configPath: fixturePath("passthrough-low-timeout"))
        XCTAssertEqual(engine.timeout, 30, "Timeout should be clamped to 30s when timeout_action is passthrough")
    }

    func testDefaultActionGate() throws {
        let engine = try RuleEngine(configPath: fixturePath("custom-timeout"))
        XCTAssertEqual(engine.defaultAction, .gate)
    }

    func testVoiceDisabledByDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertFalse(engine.voiceEnabled)
    }

    func testGracePeriodParsing() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let npmRule = engine.rules.first { $0.name == "Gate: npm install" }
        XCTAssertNotNil(npmRule)
        XCTAssertEqual(npmRule?.gracePeriod, 300)
    }

    func testGracePeriodDefaultsToZero() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let forceRule = engine.rules.first { $0.name == "Gate: force push" }
        XCTAssertNotNil(forceRule)
        XCTAssertEqual(forceRule?.gracePeriod, 0)
    }

    func testAuditDisabledByDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertFalse(engine.auditEnabled)
    }

    // MARK: - Malformed Config

    func testMalformedRuleSkipped() throws {
        let engine = try RuleEngine(configPath: fixturePath("malformed"))
        XCTAssertEqual(engine.rules.count, 0, "Malformed rules should be skipped")
    }

    func testMissingConfigThrows() {
        XCTAssertThrowsError(try RuleEngine(configPath: "/nonexistent/path.toml"))
    }

    // MARK: - HookOutput

    func testHookOutputAllow() {
        let output = HookOutput.allow(reason: "test")
        let json = output.toJSON()
        XCTAssertTrue(json.contains("\"permissionDecision\":\"allow\""))
        XCTAssertTrue(json.contains("\"permissionDecisionReason\":\"test\""))
    }

    func testHookOutputDeny() {
        let output = HookOutput.deny(reason: "blocked")
        let json = output.toJSON()
        XCTAssertTrue(json.contains("\"permissionDecision\":\"deny\""))
        XCTAssertTrue(json.contains("\"permissionDecisionReason\":\"blocked\""))
    }

    // MARK: - HookInput Parsing

    func testHookInputParsing() throws {
        let json = """
        {"tool_name":"Bash","tool_input":{"command":"ls -la","description":"List files"},"cwd":"/tmp"}
        """
        let input = try JSONDecoder().decode(HookInput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(input.toolName, "Bash")
        XCTAssertEqual(input.command, "ls -la")
        XCTAssertEqual(input.toolDescription, "List files")
        XCTAssertEqual(input.cwd, "/tmp")
    }

    func testHookInputMinimal() throws {
        let json = """
        {"tool_name":"Bash","tool_input":{}}
        """
        let input = try JSONDecoder().decode(HookInput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(input.toolName, "Bash")
        XCTAssertNil(input.command)
        XCTAssertNil(input.filePath)
        XCTAssertNil(input.cwd)
    }

    // MARK: - Wildcard Tool Matching

    func testWildcardMatchesBrowserMCPTool() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "mcp__claude-in-chrome__navigate", extraFields: ["url": "https://example.com"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: browser automation")
    }

    func testWildcardMatchesDifferentBrowserAction() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "mcp__claude-in-chrome__javascript_tool", extraFields: ["code": "alert(1)"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: browser automation")
    }

    func testWildcardMatchesFilesystemMCP() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "mcp__filesystem__write_file", extraFields: ["path": "/etc/hosts"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: all filesystem MCP")
    }

    func testExactMCPToolMatch() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "mcp__slack__send_message", extraFields: ["channel": "#general", "message": "hello"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: exact MCP tool")
    }

    func testWildcardDoesNotMatchDifferentNamespace() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        // mcp__linear__create_issue should not match mcp__claude-in-chrome__* or others
        let input = makeInput(tool: "mcp__linear__create_issue", extraFields: ["title": "Bug"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    func testObsidianWriteMatchesWithPattern() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        // mcp__obsidian__write_note matches wildcard mcp__obsidian__*
        // Pattern "write_note|delete_note|patch_note" matches because the default case
        // checks against "toolName + toolInputAsString", so the action in the tool name matches.
        let input = makeInput(tool: "mcp__obsidian__write_note", extraFields: ["path": "daily/note.md", "content": "hello"])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: Obsidian writes")
    }

    func testObsidianReadPassesThrough() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        // read_note should NOT match the write/delete pattern
        let input = makeInput(tool: "mcp__obsidian__read_note", extraFields: ["path": "daily/note.md"])
        let (rule, action) = engine.evaluate(input)
        // The wildcard matches but the pattern won't match "read_note" against write/delete
        // So it falls through to default action
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - Agent Tool Matching

    func testAgentBackgroundGated() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Agent", extraFields: [
            "prompt": "Delete all test files",
            "subagent_type": "general-purpose",
            "run_in_background": true
        ])
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: background agents")
    }

    func testAgentForegroundPassesThrough() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Agent", extraFields: [
            "prompt": "Search for TODO comments",
            "subagent_type": "Explore"
        ])
        let (rule, action) = engine.evaluate(input)
        // run_in_background is not set/true, so the pattern won't match
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - MCP HookInput Properties

    func testIsMCPTool() throws {
        let input = makeInput(tool: "mcp__obsidian__write_note", extraFields: ["path": "note.md"])
        XCTAssertTrue(input.isMCPTool)
    }

    func testIsNotMCPTool() throws {
        let input = makeInput(tool: "Bash", command: "ls")
        XCTAssertFalse(input.isMCPTool)
    }

    func testMCPNamespace() throws {
        let input = makeInput(tool: "mcp__obsidian__write_note", extraFields: ["path": "note.md"])
        XCTAssertEqual(input.mcpNamespace, "obsidian")
    }

    func testMCPAction() throws {
        let input = makeInput(tool: "mcp__obsidian__write_note", extraFields: ["path": "note.md"])
        XCTAssertEqual(input.mcpAction, "write_note")
    }

    func testMCPNamespaceWithHyphen() throws {
        let input = makeInput(tool: "mcp__claude-in-chrome__navigate", extraFields: ["url": "https://example.com"])
        XCTAssertEqual(input.mcpNamespace, "claude-in-chrome")
        XCTAssertEqual(input.mcpAction, "navigate")
    }

    func testAgentDisplaySummary() throws {
        let input = makeInput(tool: "Agent", extraFields: [
            "prompt": "Search for TODO comments in the codebase",
            "subagent_type": "Explore"
        ])
        let summary = input.displaySummary
        XCTAssertTrue(summary.contains("Agent"))
        XCTAssertTrue(summary.contains("Explore"))
        XCTAssertTrue(summary.contains("TODO"))
    }

    func testMCPDisplaySummary() throws {
        let input = makeInput(tool: "mcp__obsidian__write_note", extraFields: [
            "path": "daily/2026-03-09.md",
            "content": "Hello world",
            "title": "Daily Note"
        ])
        let summary = input.displaySummary
        XCTAssertTrue(summary.contains("obsidian"))
        XCTAssertTrue(summary.contains("write_note"))
        XCTAssertTrue(summary.contains("daily/2026-03-09.md"))
    }

    func testBashDisplaySummary() throws {
        let input = makeInput(tool: "Bash", command: "git push --force")
        XCTAssertEqual(input.displaySummary, "git push --force")
    }

    func testWriteDisplaySummary() throws {
        let input = makeInput(tool: "Write", filePath: "/Users/me/.zshrc")
        XCTAssertEqual(input.displaySummary, "Write: /Users/me/.zshrc")
    }

    // MARK: - Wildcard toolMatches Unit Tests

    func testToolMatchesExact() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertTrue(engine.toolMatches(pattern: "Bash", toolName: "Bash"))
        XCTAssertFalse(engine.toolMatches(pattern: "Bash", toolName: "Write"))
    }

    func testToolMatchesWildcard() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertTrue(engine.toolMatches(pattern: "mcp__*", toolName: "mcp__obsidian__write_note"))
        XCTAssertTrue(engine.toolMatches(pattern: "mcp__*", toolName: "mcp__slack__send_message"))
        XCTAssertFalse(engine.toolMatches(pattern: "mcp__*", toolName: "Agent"))
        XCTAssertFalse(engine.toolMatches(pattern: "mcp__*", toolName: "Bash"))
    }

    func testToolMatchesNamespaceWildcard() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertTrue(engine.toolMatches(pattern: "mcp__obsidian__*", toolName: "mcp__obsidian__write_note"))
        XCTAssertTrue(engine.toolMatches(pattern: "mcp__obsidian__*", toolName: "mcp__obsidian__read_note"))
        XCTAssertFalse(engine.toolMatches(pattern: "mcp__obsidian__*", toolName: "mcp__slack__send_message"))
    }
}
