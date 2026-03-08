import XCTest
@testable import apple_code

final class ToolRoutingTests: XCTestCase {
    private func toolNames(for prompt: String) -> [String] {
        routeTools(
            for: prompt,
            includeAppleTools: false,
            includeWebTools: false,
            includeBrowserTools: false
        ).map(\.name)
    }

    func testReadOnlyFileIntentDoesNotExposeMutatingTools() {
        let names = toolNames(for: "read the README file")

        XCTAssertTrue(names.contains(ReadFileTool().name))
        XCTAssertFalse(names.contains(WriteFileTool().name))
        XCTAssertFalse(names.contains(EditFileTool().name))
    }

    func testSearchIntentRemainsReadOnly() {
        let names = toolNames(for: "search the project for routeTools")

        XCTAssertTrue(names.contains(SearchFilesTool().name))
        XCTAssertTrue(names.contains(SearchContentTool().name))
        XCTAssertFalse(names.contains(WriteFileTool().name))
        XCTAssertFalse(names.contains(EditFileTool().name))
    }

    func testEditIntentExposesMutatingTools() {
        let names = toolNames(for: "edit Sources/AppleCode/main.swift to update routeTools")

        XCTAssertTrue(names.contains(ReadFileTool().name))
        XCTAssertTrue(names.contains(WriteFileTool().name))
        XCTAssertTrue(names.contains(EditFileTool().name))
    }

    func testCreateIntentExposesMutatingTools() {
        let names = toolNames(for: "create a file named notes.txt")

        XCTAssertTrue(names.contains(ReadFileTool().name))
        XCTAssertTrue(names.contains(WriteFileTool().name))
        XCTAssertTrue(names.contains(EditFileTool().name))
    }
}
