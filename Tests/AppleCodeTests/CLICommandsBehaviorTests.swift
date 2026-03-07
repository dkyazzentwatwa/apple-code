import XCTest
@testable import apple_code

@MainActor
final class CLICommandsBehaviorTests: XCTestCase {
    private func withPreservedWorkingDirectory(
        _ body: (String) throws -> Void
    ) rethrows {
        let originalWorkingDirectory = FileManager.default.currentDirectoryPath
        defer {
            _ = FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory)
        }
        try body(originalWorkingDirectory)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

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

    func testChangeWorkingDirectoryUpdatesSessionOnlyOnValidDirectory() throws {
        try withPreservedWorkingDirectory { originalWorkingDirectory in
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let targetDirectory = tempRoot.appendingPathComponent("subdir", isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            var session = Session(workingDir: originalWorkingDirectory)
            let targetPath = standardizedPath(targetDirectory.path)

            let result = changeWorkingDirectory(to: targetDirectory.path, session: &session)

            XCTAssertEqual(result, .success(targetPath))
            XCTAssertEqual(standardizedPath(session.workingDir), targetPath)
            XCTAssertEqual(standardizedPath(FileManager.default.currentDirectoryPath), targetPath)
        }
    }

    func testChangeWorkingDirectoryRejectsMissingPath() {
        withPreservedWorkingDirectory { originalWorkingDirectory in
            let missingPath = standardizedPath(
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true).path
            )
            var session = Session(workingDir: originalWorkingDirectory)

            let result = changeWorkingDirectory(to: missingPath, session: &session)

            XCTAssertEqual(result, .missing(missingPath))
            XCTAssertEqual(standardizedPath(session.workingDir), standardizedPath(originalWorkingDirectory))
            XCTAssertEqual(
                standardizedPath(FileManager.default.currentDirectoryPath),
                standardizedPath(originalWorkingDirectory)
            )
        }
    }

    func testChangeWorkingDirectoryRejectsFilePath() throws {
        try withPreservedWorkingDirectory { originalWorkingDirectory in
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            let fileURL = tempRoot.appendingPathComponent("note.txt", isDirectory: false)
            try Data("hello".utf8).write(to: fileURL)

            var session = Session(workingDir: originalWorkingDirectory)
            let filePath = standardizedPath(fileURL.path)

            let result = changeWorkingDirectory(to: fileURL.path, session: &session)

            XCTAssertEqual(result, .notDirectory(filePath))
            XCTAssertEqual(standardizedPath(session.workingDir), standardizedPath(originalWorkingDirectory))
            XCTAssertEqual(
                standardizedPath(FileManager.default.currentDirectoryPath),
                standardizedPath(originalWorkingDirectory)
            )
        }
    }
}
