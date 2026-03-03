import XCTest
@testable import apple_code

final class CLICommandsTests: XCTestCase {
    func testParseQuitAliases() {
        assertIsQuit(parseCommand("/quit"))
        assertIsQuit(parseCommand(":q"))
        assertIsQuit(parseCommand("/exit"))
    }

    func testParseHistoryWithAndWithoutCount() {
        assertHistory(parseCommand("/history"), expected: nil)
        assertHistory(parseCommand("/history 25"), expected: 25)
    }

    func testParseResumeRequiresValidUUID() {
        let id = UUID()
        let command = parseCommand("/resume \(id.uuidString)")

        switch command {
        case .resumeSession(let parsed):
            XCTAssertEqual(parsed, id)
        default:
            XCTFail("Expected resumeSession, got \(command)")
        }

        assertIsNone(parseCommand("/resume nope"))
    }

    func testParseChangeDirectoryRequiresArgument() {
        switch parseCommand("/cd /tmp") {
        case .changeDirectory(let path):
            XCTAssertEqual(path, "/tmp")
        default:
            XCTFail("Expected changeDirectory")
        }

        assertIsNone(parseCommand("/cd"))
    }

    func testParseThemeAndUISupportEmptyArg() {
        switch parseCommand("/theme") {
        case .setTheme(let value):
            XCTAssertNil(value)
        default:
            XCTFail("Expected setTheme(nil)")
        }

        switch parseCommand("/ui framed") {
        case .setUI(let value):
            XCTAssertEqual(value, "framed")
        default:
            XCTFail("Expected setUI(\"framed\")")
        }
    }

    func testParseNonCommandInputReturnsNone() {
        assertIsNone(parseCommand("just chat"))
    }

    private func assertHistory(_ command: CLICommand, expected: Int?, file: StaticString = #filePath, line: UInt = #line) {
        switch command {
        case .showHistory(let count):
            XCTAssertEqual(count, expected, file: file, line: line)
        default:
            XCTFail("Expected showHistory", file: file, line: line)
        }
    }

    private func assertIsQuit(_ command: CLICommand, file: StaticString = #filePath, line: UInt = #line) {
        guard case .quit = command else {
            XCTFail("Expected quit", file: file, line: line)
            return
        }
    }

    private func assertIsNone(_ command: CLICommand, file: StaticString = #filePath, line: UInt = #line) {
        guard case .none = command else {
            XCTFail("Expected none", file: file, line: line)
            return
        }
    }
}
