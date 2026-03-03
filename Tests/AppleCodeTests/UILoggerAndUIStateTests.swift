import XCTest
import Foundation
@testable import apple_code

final class UILoggerAndUIStateTests: XCTestCase {
    func testUILoggerConfigureAndLogWritesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apple-code-logger-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        UILogger.shared.configure(directory: dir)
        UILogger.shared.log("first")
        UILogger.shared.log("second")

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)

        let content = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(content.contains("first"))
        XCTAssertTrue(content.contains("second"))
    }

    func testUIStateComputedRowsAndHeight() {
        let state = UIState(width: 120, height: 40, bannerHeight: 9, footerHeight: 3)
        XCTAssertEqual(state.contentTopRow, 11)
        XCTAssertEqual(state.contentBottomRow, 35)
        XCTAssertEqual(state.inputRow, 36)
        XCTAssertEqual(state.contentHeight, 25)

        let compact = UIState(width: 40, height: 8, bannerHeight: 5, footerHeight: 5)
        XCTAssertGreaterThanOrEqual(compact.contentHeight, 3)
    }
}
