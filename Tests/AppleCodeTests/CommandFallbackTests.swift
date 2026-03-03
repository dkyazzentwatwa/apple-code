import XCTest
@testable import apple_code

final class CommandFallbackTests: XCTestCase {
    func testDetectCommandIntentPrompt() {
        XCTAssertTrue(isCommandIntentPrompt("run ls -la"))
        XCTAssertTrue(isCommandIntentPrompt("please execute command pwd"))
        XCTAssertFalse(isCommandIntentPrompt("write me a poem"))
    }

    func testLooksLikeCommandRefusal() {
        XCTAssertTrue(looksLikeCommandRefusal("I can't run shell command here."))
        XCTAssertFalse(looksLikeCommandRefusal("I can run this command for you"))
    }

    func testExtractShellCommandFromPrefixesAndQuotes() {
        XCTAssertEqual(extractShellCommand(from: "run command ls -la"), "ls -la")
        XCTAssertEqual(extractShellCommand(from: "execute `pwd`"), "pwd")
        XCTAssertEqual(extractShellCommand(from: "run \"echo hi\""), "echo hi")
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
}
