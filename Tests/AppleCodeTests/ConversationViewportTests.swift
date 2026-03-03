import XCTest
@testable import apple_code

final class ConversationViewportTests: XCTestCase {
    func testAppendAndRecentEntries() {
        let viewport = ConversationViewport(maxEntries: 3)
        viewport.append(role: "you", content: "one")
        viewport.append(role: "assistant", content: "two")
        viewport.append(role: "system", content: "three")
        viewport.append(role: "you", content: "four")

        let recent = viewport.recentEntries(limit: 2)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].content, "three")
        XCTAssertEqual(recent[1].content, "four")

        XCTAssertNil(viewport.entry(id: 1))
        XCTAssertEqual(viewport.entry(id: 4)?.content, "four")
    }

    func testVisibleLinesAndScrollState() {
        let viewport = ConversationViewport(maxEntries: 20)
        for i in 1...8 {
            viewport.append(role: "you", content: "message \(i)")
        }

        let bottom = viewport.visibleLines(width: 40, maxLines: 5)
        XCTAssertEqual(bottom.count, 5)

        viewport.scrollBy(2, width: 40, maxLines: 5)
        let state = viewport.scrollState(width: 40, maxLines: 5)
        XCTAssertGreaterThan(state.maxOffset, 0)
        XCTAssertEqual(state.offset, 2)

        let scrolled = viewport.visibleLines(width: 40, maxLines: 5)
        XCTAssertEqual(scrolled.count, 5)
        XCTAssertNotEqual(bottom, scrolled)

        viewport.scrollToBottom()
        XCTAssertEqual(viewport.scrollState(width: 40, maxLines: 5).offset, 0)
    }

    func testResetClearsEntriesAndCache() {
        let viewport = ConversationViewport()
        viewport.append(role: "you", content: "hello")
        _ = viewport.visibleLines(width: 20, maxLines: 3)
        viewport.reset()

        XCTAssertTrue(viewport.entries.isEmpty)
        XCTAssertTrue(viewport.visibleLines(width: 20, maxLines: 3).isEmpty)
    }
}
