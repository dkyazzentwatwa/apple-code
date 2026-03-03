import XCTest
import Foundation
@testable import apple_code

final class ToolBasicsTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apple-code-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWriteReadListSearchContentAndFilesTools() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("notes.txt")
        let nestedDir = dir.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let swiftURL = nestedDir.appendingPathComponent("main.swift")

        let writeResult = try await WriteFileTool().call(arguments: .init(path: fileURL.path, content: "hello world\nsecond line"))
        XCTAssertTrue(writeResult.contains("Successfully wrote"))

        let readResult = try await ReadFileTool().call(arguments: .init(path: fileURL.path))
        XCTAssertTrue(readResult.contains("hello world"))

        try "print(\"hello world\")".write(to: swiftURL, atomically: true, encoding: .utf8)

        let listResult = try await ListDirectoryTool().call(arguments: .init(path: dir.path, recursive: false))
        XCTAssertTrue(listResult.contains("notes.txt"))
        XCTAssertTrue(listResult.contains("src/"))

        let recursiveList = try await ListDirectoryTool().call(arguments: .init(path: dir.path, recursive: true))
        XCTAssertTrue(recursiveList.contains("src/main.swift"))

        let fileSearch = try await SearchFilesTool().call(arguments: .init(pattern: "*.swift", path: dir.path))
        XCTAssertTrue(fileSearch.contains("src/main.swift"))

        let contentSearch = try await SearchContentTool().call(arguments: .init(pattern: "hello", path: dir.path, filePattern: "*.swift"))
        XCTAssertTrue(contentSearch.contains("src/main.swift:1:"))
    }

    func testRunCommandToolHandlesNormalBlockedAndTimeout() async throws {
        let ok = try await RunCommandTool().call(arguments: .init(command: "echo run-ok", timeout: 5))
        XCTAssertTrue(ok.contains("run-ok"))

        let blocked = try await RunCommandTool().call(arguments: .init(command: "rm -rf /tmp/fake", timeout: 5))
        XCTAssertTrue(blocked.contains("Command blocked for safety"))

        let timed = try await RunCommandTool().call(arguments: .init(command: "sleep 2", timeout: 1))
        XCTAssertTrue(timed.contains("[timed out after 1s]"))
    }
}
