import XCTest
@testable import apple_code

@MainActor
final class CLICommandsBehaviorTests: XCTestCase {
    func testParseAdditionalAliasesAndArguments() {
        guard case .listSessions = parseCommand("/list-sessions") else {
            return XCTFail("Expected listSessions")
        }
        guard case .showHistory(let count) = parseCommand(":hist 7") else {
            return XCTFail("Expected showHistory")
        }
        XCTAssertEqual(count, 7)

        guard case .openSettings = parseCommand("/settings") else {
            return XCTFail("Expected openSettings")
        }
        guard case .switchSession(let arg) = parseCommand("/session next") else {
            return XCTFail("Expected switchSession")
        }
        XCTAssertEqual(arg, "next")
        guard case .setTheme(let theme) = parseCommand("/theme ocean") else {
            return XCTFail("Expected setTheme")
        }
        XCTAssertEqual(theme, "ocean")
    }

    func testPrintHelpAndSessionHandlersExecute() async {
        printHelp()

        let manager = SessionManager.shared
        var session = manager.createSession(workingDir: "/tmp")
        session.addMessage(role: "user", content: "hello")
        try? manager.saveSession(session)

        let resumed = await handleResumeSession(id: session.id)
        XCTAssertEqual(resumed?.id, session.id)

        await handleDeleteSession(id: session.id)
        XCTAssertFalse(manager.listSessions().contains(where: { $0.id == session.id }))
    }
}
