import XCTest
import FoundationModels
@testable import apple_code

final class RouteToolsTests: XCTestCase {
    private func names(_ tools: [any Tool]) -> Set<String> {
        Set(tools.map { $0.name })
    }

    func testFollowupCreateIntentSelectsFilesystemTools() {
        let selected = routeTools(
            for: "ok create that",
            includeAppleTools: true,
            includeWebTools: true,
            includeBrowserTools: true
        )
        let toolNames = names(selected)
        XCTAssertTrue(toolNames.contains("writeFile"), "Expected writeFile in \(toolNames)")
        XCTAssertTrue(toolNames.contains("readFile"), "Expected readFile in \(toolNames)")
        XCTAssertTrue(toolNames.contains("listDirectory"), "Expected listDirectory in \(toolNames)")
    }

    func testExplicitFileCreateStillSelectsFilesystemTools() {
        let selected = routeTools(
            for: "create a file called main.swift",
            includeAppleTools: true,
            includeWebTools: true,
            includeBrowserTools: true
        )
        let toolNames = names(selected)
        XCTAssertTrue(toolNames.contains("writeFile"))
    }
}
