import XCTest
@testable import apple_code

@MainActor
final class SessionAndDiscoveryTests: XCTestCase {
    func testSessionAddMessageAndDecodeDefaults() throws {
        var session = Session(workingDir: "/tmp")
        session.addMessage(role: "user", content: "hello")
        XCTAssertEqual(session.messages.count, 1)

        let json = """
        {
          "id": "\(session.id.uuidString)",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "messages": [],
          "workingDir": "/tmp"
        }
        """
        let decoded = try JSONDecoder.iso8601.decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.uiMode, .classic)
        XCTAssertEqual(decoded.activeThemeName, TUITheme.wow.name)
    }

    func testSessionManagerCreateSaveLoadListDelete() throws {
        let manager = SessionManager.shared
        var session = manager.createSession(workingDir: "/tmp", uiMode: .framed, activeThemeName: "ocean")
        session.addMessage(role: "assistant", content: "hello")

        try manager.saveSession(session)
        let loaded = try manager.loadSession(id: session.id)
        XCTAssertEqual(loaded.id, session.id)
        XCTAssertEqual(loaded.messages.count, 1)

        let listed = manager.listSessions()
        XCTAssertTrue(listed.contains(where: { $0.id == session.id }))

        try manager.deleteSession(id: session.id)
        XCTAssertFalse(manager.listSessions().contains(where: { $0.id == session.id }))
    }

    func testOllamaPreferredDefaultModelSelection() {
        XCTAssertNil(OllamaModelDiscovery.preferredDefaultModel(from: []))
        XCTAssertEqual(
            OllamaModelDiscovery.preferredDefaultModel(from: ["foo:1b", "qwen3.5:2b"]),
            "qwen3.5:2b"
        )
        XCTAssertEqual(
            OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5:4b", "qwen3.5:2b"]),
            "qwen3.5:4b"
        )
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
