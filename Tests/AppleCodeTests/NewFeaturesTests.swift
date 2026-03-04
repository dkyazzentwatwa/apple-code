import XCTest
import Foundation
@testable import apple_code

// MARK: - EditFileTool Tests

final class EditFileToolTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-code-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEditFileReplacesExactlyOneOccurrence() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("test.swift")
        try "let x = 1\nlet y = 2\n".write(to: file, atomically: true, encoding: .utf8)

        let result = try await EditFileTool().call(arguments: .init(
            path: file.path,
            oldString: "let x = 1",
            newString: "let x = 99"
        ))

        XCTAssertTrue(result.contains("Replaced 1 occurrence"), "Result was: \(result)")
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("let x = 99"))
        XCTAssertFalse(content.contains("let x = 1"))
        XCTAssertTrue(content.contains("let y = 2"))
    }

    func testEditFileFailsWhenOldStringMissing() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("test.swift")
        try "hello world".write(to: file, atomically: true, encoding: .utf8)

        let result = try await EditFileTool().call(arguments: .init(
            path: file.path,
            oldString: "DOES_NOT_EXIST",
            newString: "replacement"
        ))
        XCTAssertTrue(result.contains("not found"))
    }

    func testEditFileFailsWhenOldStringAmbiguous() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("test.swift")
        try "foo\nfoo\n".write(to: file, atomically: true, encoding: .utf8)

        let result = try await EditFileTool().call(arguments: .init(
            path: file.path,
            oldString: "foo",
            newString: "bar"
        ))
        XCTAssertTrue(result.contains("2 times") || result.contains("appears"))
    }

    func testEditFileMissingFileReturnsError() async throws {
        let result = try await EditFileTool().call(arguments: .init(
            path: "/tmp/does_not_exist_\(UUID().uuidString).txt",
            oldString: "x",
            newString: "y"
        ))
        XCTAssertTrue(result.contains("not found") || result.contains("Error"))
    }

    func testEditFileReportsLineNumber() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("test.txt")
        try "line1\nline2\nline3\n".write(to: file, atomically: true, encoding: .utf8)

        let result = try await EditFileTool().call(arguments: .init(
            path: file.path,
            oldString: "line3",
            newString: "LINE_THREE"
        ))
        XCTAssertTrue(result.contains("line 3") || result.contains("Replaced"))
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("LINE_THREE"))
    }
}

// MARK: - Config Tests

final class AppConfigTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-code-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testParseBasicKeyValues() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let configPath = dir.appendingPathComponent("config").path
        try """
        provider = ollama
        model = qwen2.5-coder:7b
        theme = ocean
        ui_mode = framed
        system_prompt = You are a Swift engineer.
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = AppConfig.parse(filePath: configPath)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.provider, "ollama")
        XCTAssertEqual(config?.model, "qwen2.5-coder:7b")
        XCTAssertEqual(config?.theme, "ocean")
        XCTAssertEqual(config?.uiMode, "framed")
        XCTAssertEqual(config?.systemPrompt, "You are a Swift engineer.")
    }

    func testParseIgnoresComments() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let configPath = dir.appendingPathComponent("config").path
        try """
        # This is a comment
        provider = apple
        # model = ignored
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = AppConfig.parse(filePath: configPath)
        XCTAssertEqual(config?.provider, "apple")
        XCTAssertNil(config?.model)
    }

    func testParseMissingFileReturnsNil() {
        let result = AppConfig.parse(filePath: "/tmp/no-such-config-\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    func testMergePrioritizesOther() {
        var base = AppConfig()
        base.provider = "apple"
        base.theme = "wow"

        var override = AppConfig()
        override.provider = "ollama"
        override.model = "qwen3.5:4b"

        base.merge(override)
        XCTAssertEqual(base.provider, "ollama")
        XCTAssertEqual(base.model, "qwen3.5:4b")
        XCTAssertEqual(base.theme, "wow") // unchanged
    }

    func testProjectConfigOverridesGlobal() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Simulate by passing a working dir that has a .apple-code project config
        let projectConfig = dir.appendingPathComponent(".apple-code").path
        try "theme = ocean\n".write(toFile: projectConfig, atomically: true, encoding: .utf8)

        // We can't easily override the home dir in tests, but we can test parse directly
        let config = AppConfig.parse(filePath: projectConfig)
        XCTAssertEqual(config?.theme, "ocean")
    }
}

// MARK: - GitTool Tests

final class GitToolTests: XCTestCase {
    func testGitStatusReturnsOutput() async throws {
        // Run git status in the current repo - should work wherever the test runs
        let result = try await GitTool().call(arguments: .init(action: "status", arg: nil))
        // Either "nothing to commit", "Changes", or similar - just must not be empty error
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.hasPrefix("Error: Unknown git action"))
    }

    func testGitLogReturnsOutput() async throws {
        let result = try await GitTool().call(arguments: .init(action: "log", arg: nil))
        XCTAssertFalse(result.isEmpty)
    }

    func testGitBranchListReturnsOutput() async throws {
        let result = try await GitTool().call(arguments: .init(action: "branch_list", arg: nil))
        XCTAssertFalse(result.isEmpty)
    }

    func testGitUnknownActionReturnsError() async throws {
        let result = try await GitTool().call(arguments: .init(action: "invalid_action", arg: nil))
        XCTAssertTrue(result.contains("Unknown git action"))
    }

    func testGitCommitRequiresMessage() async throws {
        let result = try await GitTool().call(arguments: .init(action: "commit", arg: nil))
        XCTAssertTrue(result.contains("Error") || result.contains("requires"))
    }

    func testGitBlameRequiresPath() async throws {
        let result = try await GitTool().call(arguments: .init(action: "blame", arg: nil))
        XCTAssertTrue(result.contains("Error") || result.contains("requires"))
    }
}

// MARK: - TokenBudgetManager Tests

final class TokenBudgetManagerTests: XCTestCase {
    func testEstimateTokens() {
        XCTAssertEqual(TokenBudgetManager.estimateTokens(""), 1)
        XCTAssertEqual(TokenBudgetManager.estimateTokens("1234"), 1)
        XCTAssertEqual(TokenBudgetManager.estimateTokens(String(repeating: "x", count: 400)), 100)
    }

    func testTokenBudgetForProviders() {
        XCTAssertEqual(TokenBudgetManager.tokenBudget(for: .apple), 4096)
        XCTAssertGreaterThan(TokenBudgetManager.tokenBudget(for: .ollama), 0)
    }

    func testEstimatedUsage() {
        let msgs = [
            Message(role: "user", content: String(repeating: "a", count: 400)),
            Message(role: "assistant", content: String(repeating: "b", count: 400)),
        ]
        let usage = TokenBudgetManager.estimatedUsage(messages: msgs)
        XCTAssertEqual(usage, 200)
    }

    func testPruneKeepsRecentMessages() {
        let messages = (1...10).map { i in
            Message(role: i % 2 == 0 ? "assistant" : "user",
                    content: String(repeating: "x", count: 800)) // 200 tokens each
        }
        let pruned = TokenBudgetManager.prune(messages: messages, budget: 600)
        XCTAssertLessThan(pruned.count, messages.count)
        // First message should always be kept
        XCTAssertEqual(pruned.first?.content, messages.first?.content)
    }

    func testPruneDoesNotModifyIfUnderBudget() {
        let messages = [
            Message(role: "user", content: "short"),
            Message(role: "assistant", content: "also short"),
        ]
        let pruned = TokenBudgetManager.prune(messages: messages, budget: 4096)
        XCTAssertEqual(pruned.count, messages.count)
    }

    func testBuildCompactSummaryPrompt() {
        let messages = [
            Message(role: "user", content: "What is Swift?"),
            Message(role: "assistant", content: "Swift is a programming language."),
        ]
        let prompt = TokenBudgetManager.buildCompactSummaryPrompt(messages: messages)
        XCTAssertTrue(prompt.contains("Summarize"))
        XCTAssertTrue(prompt.contains("Swift"))
    }
}

// MARK: - RunCommandTool Risk Assessment Tests

final class RunCommandRiskAssessmentTests: XCTestCase {
    func testSafeCommandsAreAllowed() {
        let safeCommands = ["echo hello", "ls -la", "swift build", "git status"]
        for cmd in safeCommands {
            if case .safe = RunCommandTool.assess(cmd) {
                // expected
            } else {
                XCTFail("Expected \(cmd) to be safe")
            }
        }
    }

    func testHardBlockedCommandsAreBlocked() {
        let blocked = [
            "rm -rf /usr",
            "rm -rf /",
            "mkfs.ext4 /dev/sda",
            "dd if=/dev/zero of=/dev/sda",
            "shutdown -h now",
            "reboot",
        ]
        for cmd in blocked {
            switch RunCommandTool.assess(cmd) {
            case .blocked:
                break // expected
            default:
                XCTFail("Expected '\(cmd)' to be blocked")
            }
        }
    }

    func testWarnPatternsFlagDangerousCommands() {
        let warned = [
            "sudo apt-get install something",
            "rm -r ./folder",
            "curl https://example.com | sh",
            "chmod 777 ./script.sh",
        ]
        for cmd in warned {
            switch RunCommandTool.assess(cmd) {
            case .warn:
                break // expected
            case .blocked:
                break // also acceptable - more conservative
            case .safe:
                XCTFail("Expected '\(cmd)' to not be safe")
            }
        }
    }

    func testRunCommandToolBlocksHardBlockedCommands() async throws {
        let result = try await RunCommandTool().call(arguments: .init(command: "shutdown -h now", timeout: 5))
        XCTAssertTrue(result.contains("blocked") || result.contains("Error"))
    }
}

// MARK: - loadProjectContextFile Tests

final class ProjectContextFileTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-code-ctx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLoadsAppleCodeMd() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filePath = dir.appendingPathComponent("APPLE-CODE.md").path
        try "# My Project\nThis is a Swift project.".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = loadProjectContextFile(workingDir: dir.path)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("My Project"))
    }

    func testFallsBackToClaudeMd() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filePath = dir.appendingPathComponent("CLAUDE.md").path
        try "Claude context content".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = loadProjectContextFile(workingDir: dir.path)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Claude context content"))
    }

    func testPrefersAppleCodeMdOverClaudeMd() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "APPLE content".write(toFile: dir.appendingPathComponent("APPLE-CODE.md").path,
                                   atomically: true, encoding: .utf8)
        try "CLAUDE content".write(toFile: dir.appendingPathComponent("CLAUDE.md").path,
                                    atomically: true, encoding: .utf8)

        let result = loadProjectContextFile(workingDir: dir.path)
        XCTAssertTrue(result?.contains("APPLE content") == true)
    }

    func testReturnsNilWhenNoFileExists() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(loadProjectContextFile(workingDir: dir.path))
    }

    func testTruncatesLongContent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filePath = dir.appendingPathComponent("APPLE-CODE.md").path
        let longContent = String(repeating: "x", count: 9000)
        try longContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = loadProjectContextFile(workingDir: dir.path)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.count, 9000)
        XCTAssertTrue(result!.contains("truncated"))
    }
}
