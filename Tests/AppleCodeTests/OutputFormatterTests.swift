import XCTest
@testable import apple_code

final class OutputFormatterTests: XCTestCase {
    func testVerboseReturnsOriginalMessage() {
        let message = "line1\nline2"
        XCTAssertEqual(OutputFormatter.format(message, verbose: true), message)
    }

    func testNonToolHeavyReturnsOriginal() {
        let message = "Short response"
        XCTAssertEqual(OutputFormatter.format(message, verbose: false), message)
    }

    func testToolHeavySummarizesAndTruncatesPreview() {
        let lines = (1...20).map { "\($0). item" }.joined(separator: "\n")
        let formatted = OutputFormatter.format(lines, verbose: false)
        XCTAssertTrue(formatted.contains("[summary] 20 lines"))
        XCTAssertTrue(formatted.contains("showing first 10"))
        XCTAssertTrue(formatted.contains("1. item"))
        XCTAssertFalse(formatted.contains("20. item"))
    }

    func testLongMessageTriggersSummaryEvenWithoutSpecialMarkers() {
        let long = String(repeating: "a", count: 2600)
        let formatted = OutputFormatter.format(long, verbose: false)
        XCTAssertTrue(formatted.hasPrefix("[summary]"))
    }
}
