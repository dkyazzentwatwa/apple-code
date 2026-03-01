import Foundation
import FoundationModels
import SQLite3

struct MessagesTool: Tool {
    let name = "messages"
    let description = "Apple Messages: list_recent_chats, search"

    @Generable
    struct Arguments {
        @Guide(description: "Action name")
        let action: String
        @Guide(description: "Search text")
        let query: String?
    }

    private static let dbPath = NSHomeDirectory() + "/Library/Messages/chat.db"

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list_recent_chats":
            return listRecentChats(limit: 10)
        case "search":
            guard let query = arguments.query else {
                return "Error: 'query' is required for search"
            }
            return search(query: query, limit: 20)
        default:
            return "Unknown action: \(arguments.action). Available: list_recent_chats, search"
        }
    }

    // MARK: - Actions

    private func listRecentChats(limit: Int) -> String {
        guard let db = openDB() else {
            return "Error: Cannot access Messages database. Grant Full Disk Access in System Settings > Privacy."
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT DISTINCT h.id AS handle, h.service
        FROM handle h
        JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
        JOIN chat c ON chj.chat_id = c.ROWID
        ORDER BY c.last_read_message_timestamp DESC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return "Error: Failed to prepare query"
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let handle = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "unknown"
            let service = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            results.append("\(handle)  (\(service))")
        }

        return results.isEmpty ? "No recent chats found." : results.joined(separator: "\n")
    }

    private func search(query: String, limit: Int) -> String {
        guard let db = openDB() else {
            return "Error: Cannot access Messages database. Grant Full Disk Access in System Settings > Privacy."
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT m.text, COALESCE(h.id, 'unknown') AS handle, m.date
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.text LIKE ?
        ORDER BY m.ROWID DESC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return "Error: Failed to prepare query"
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let text = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let handle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "unknown"
            let truncated = text.count > 120 ? String(text.prefix(120)) + "..." : text
            results.append("\(handle):  \(truncated)")
        }

        return results.isEmpty ? "No messages found matching '\(query)'." : results.joined(separator: "\n")
    }

    // MARK: - DB helper

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = "file:\(Self.dbPath)?mode=ro"
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_exec(db, "PRAGMA query_only=ON", nil, nil, nil)
        return db
    }
}
