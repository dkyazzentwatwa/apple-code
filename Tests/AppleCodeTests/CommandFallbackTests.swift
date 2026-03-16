import XCTest
@testable import apple_code

final class CommandFallbackTests: XCTestCase {
    private var previousPolicy: ToolSafetyPolicy?

    override func setUp() {
        super.setUp()
        previousPolicy = ToolSafety.shared.currentPolicy()
        ToolSafety.shared.configure(
            ToolSafetyPolicy.make(
                profile: .compatibility,
                workingDirectory: FileManager.default.currentDirectoryPath,
                additionalAllowedRoots: [FileManager.default.temporaryDirectory.path],
                allowedHosts: [],
                allowPrivateNetwork: true,
                allowDangerousWithoutConfirmation: true,
                allowAutomaticFallbackExecution: true
            )
        )
    }

    override func tearDown() {
        if let previousPolicy {
            ToolSafety.shared.configure(previousPolicy)
        }
        super.tearDown()
    }

    func testDetectCommandIntentPrompt() {
        XCTAssertTrue(isCommandIntentPrompt("run ls -la"))
        XCTAssertTrue(isCommandIntentPrompt("please execute command pwd"))
        XCTAssertTrue(isCommandIntentPrompt("git status"))
        XCTAssertFalse(isCommandIntentPrompt("write me a poem"))
    }

    func testLooksLikeCommandRefusal() {
        XCTAssertTrue(looksLikeCommandRefusal("I can't run shell command here."))
        XCTAssertTrue(looksLikeCommandRefusal("I'm sorry, I can't access system tools like git status directly."))
        XCTAssertFalse(looksLikeCommandRefusal("I can run this command for you"))
    }

    func testExtractShellCommandFromPrefixesAndQuotes() {
        XCTAssertEqual(extractShellCommand(from: "run command ls -la"), "ls -la")
        XCTAssertEqual(extractShellCommand(from: "execute `pwd`"), "pwd")
        XCTAssertEqual(extractShellCommand(from: "run \"echo hi\""), "echo hi")
        XCTAssertEqual(extractShellCommand(from: "✶  apple-code ›   git status"), "git status")
        XCTAssertEqual(extractShellCommand(from: "git status"), "git status")
        XCTAssertNil(extractShellCommand(from: "just chat"))
    }

    func testResolveCommandRefusalFallbackRunsCommand() async {
        let result = await resolveCommandRefusalFallback(
            userPrompt: "run command echo hello",
            modelReply: "I can't run shell commands.",
            timeoutSeconds: 5
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("Command output (`echo hello`)") == true)
        XCTAssertTrue(result?.contains("hello") == true)
    }

    func testResolveCommandRefusalFallbackRunsRawCommand() async {
        let result = await resolveCommandRefusalFallback(
            userPrompt: "git status",
            modelReply: "I'm sorry, I can't access system tools like git status directly.",
            timeoutSeconds: 5
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("Command output (`git status`)") == true)
    }

    func testResolveFilesystemRefusalFallbackReadsReadme() async {
        let result = await resolveFilesystemRefusalFallback(
            userPrompt: "read the file README.md",
            modelReply: "null"
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("File content (`README.md`)") == true)
        XCTAssertTrue(result?.contains("# apple-code") == true)
    }

    func testResolveFilesystemRefusalFallbackListsCurrentDirectory() async {
        let result = await resolveFilesystemRefusalFallback(
            userPrompt: "whats in this folder",
            modelReply: "I can't access system tools directly."
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("Directory listing (`.`)") == true)
        XCTAssertTrue(result?.contains("README.md") == true)
    }
}
