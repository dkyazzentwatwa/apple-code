import XCTest
@testable import apple_code

final class CodexModelClientTests: XCTestCase {
    private var previousPolicy: ToolSafetyPolicy?

    override func setUp() {
        super.setUp()
        previousPolicy = ToolSafety.shared.currentPolicy()
    }

    override func tearDown() {
        if let previousPolicy {
            ToolSafety.shared.configure(previousPolicy)
        }
        super.tearDown()
    }

    func testCodexClientBuildsExecInvocationAndReadsLastMessage() async throws {
        configureSecurity(.secure)
        let runner = CapturingCodexRunner(finalMessage: "Codex says hi")
        let config = ModelConfig(provider: .codex, model: "gpt-5.2", baseURL: nil)
        let client = CodexModelClient(config: config, model: config.model, runner: runner)

        let response = try await client.respond(
            prompt: "review this",
            tools: [],
            instructions: "You are apple-code."
        )

        XCTAssertEqual(response, "Codex says hi")
        let args = await runner.arguments
        XCTAssertEqual(args.first, "exec")
        XCTAssertTrue(args.contains("--cd"))
        XCTAssertTrue(args.contains(FileManager.default.currentDirectoryPath))
        XCTAssertTrue(args.contains("--color"))
        XCTAssertTrue(args.contains("never"))
        XCTAssertTrue(args.contains("--output-last-message"))
        XCTAssertTrue(args.contains("--sandbox"))
        XCTAssertTrue(args.contains("read-only"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("gpt-5.2"))
        XCTAssertEqual(args.last, "-")

        let stdin = await runner.stdin
        XCTAssertTrue(stdin.contains("You are apple-code."))
        XCTAssertTrue(stdin.contains("review this"))
    }

    func testCodexClientMapsBalancedSecurityToWorkspaceWrite() async throws {
        configureSecurity(.balanced)
        let runner = CapturingCodexRunner(finalMessage: "ok")
        let client = CodexModelClient(
            config: ModelConfig(provider: .codex, model: nil, baseURL: nil),
            runner: runner
        )

        _ = try await client.respond(prompt: "hello", tools: [], instructions: "system")

        let args = await runner.arguments
        XCTAssertTrue(args.contains("--sandbox"))
        XCTAssertTrue(args.contains("workspace-write"))
        XCTAssertFalse(args.contains("--model"))
    }

    func testCodexClientReportsProcessFailure() async {
        let runner = CapturingCodexRunner(
            finalMessage: nil,
            result: CodexProcessResult(stdout: "out", stderr: "bad flag", exitCode: 2)
        )
        let client = CodexModelClient(
            config: ModelConfig(provider: .codex, model: nil, baseURL: nil),
            runner: runner
        )

        do {
            _ = try await client.respond(prompt: "hello", tools: [], instructions: "system")
            XCTFail("Expected Codex failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("exit code 2"))
            XCTAssertTrue(error.localizedDescription.contains("bad flag"))
        }
    }

    private func configureSecurity(_ profile: SecurityProfile) {
        ToolSafety.shared.configure(
            ToolSafetyPolicy.make(
                profile: profile,
                workingDirectory: FileManager.default.currentDirectoryPath,
                additionalAllowedRoots: [],
                allowedHosts: [],
                allowPrivateNetwork: nil,
                allowDangerousWithoutConfirmation: nil,
                allowAutomaticFallbackExecution: nil
            )
        )
    }
}

private actor CapturingCodexRunner: CodexProcessRunning {
    private(set) var arguments: [String] = []
    private(set) var stdin: String = ""
    private let finalMessage: String?
    private let result: CodexProcessResult

    init(
        finalMessage: String?,
        result: CodexProcessResult = CodexProcessResult(stdout: "", stderr: "", exitCode: 0)
    ) {
        self.finalMessage = finalMessage
        self.result = result
    }

    func runCodex(
        arguments: [String],
        stdin: String,
        environment: [String: String]
    ) async throws -> CodexProcessResult {
        self.arguments = arguments
        self.stdin = stdin
        if let finalMessage,
           let outputIndex = arguments.firstIndex(of: "--output-last-message"),
           arguments.indices.contains(outputIndex + 1) {
            try finalMessage.write(
                toFile: arguments[outputIndex + 1],
                atomically: true,
                encoding: .utf8
            )
        }
        return result
    }
}
