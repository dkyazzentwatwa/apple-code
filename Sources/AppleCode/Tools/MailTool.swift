import Foundation
import FoundationModels

struct MailTool: Tool {
    let name = "mail"
    let description = "Apple Mail: list_unread, search, get_content"

    @Generable
    struct Arguments {
        @Guide(description: "Action name")
        let action: String
        @Guide(description: "Query or message ID")
        let query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list_unread":
            return listUnread()
        case "search":
            guard let query = arguments.query else {
                return "Error: 'query' is required for search"
            }
            return search(query: query)
        case "get_content":
            guard let query = arguments.query else {
                return "Error: 'query' (message ID) is required for get_content"
            }
            return getContent(messageId: query)
        default:
            return "Unknown action: \(arguments.action). Available: list_unread, search, get_content"
        }
    }

    // MARK: - Actions

    private func listUnread(limit: Int = 20) -> String {
        let records = fetchRaw(unreadOnly: true, limit: limit)
        return AppleScriptRunner.formatRecords(records) { r in
            "\(r["sender"] ?? "")  |  \(r["subject"] ?? "")  [\(r["date"] ?? "")]"
        }
    }

    private func search(query: String, limit: Int = 20) -> String {
        let allMsgs = fetchRaw(unreadOnly: false, limit: 200, maxAgeDays: 30)
        let q = query.lowercased()
        let matches = allMsgs.filter { m in
            (m["sender"] ?? "").lowercased().contains(q) ||
            (m["subject"] ?? "").lowercased().contains(q) ||
            (m["body_preview"] ?? "").lowercased().contains(q)
        }.prefix(limit)
        return AppleScriptRunner.formatRecords(Array(matches)) { r in
            "\(r["sender"] ?? "")  |  \(r["subject"] ?? "")  [\(r["date"] ?? "")]"
        }
    }

    private func getContent(messageId: String) -> String {
        let escId = messageId.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            try
                set matchedMsg to first message of inbox whose id as text is "\(escId)"
                return content of matchedMsg as text
            on error
                return ""
            end try
        end tell
        """
        return AppleScriptRunner.run(script, timeout: 30) ?? "Message not found."
    }

    // MARK: - Internal fetch

    private func fetchRaw(unreadOnly: Bool, limit: Int = 50, maxAgeDays: Int = 30) -> [[String: String]] {
        let readClause = unreadOnly ? "whose read status is false" : ""

        let script = """
        on sanitise(txt)
            set AppleScript's text item delimiters to (ASCII character 9)
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            set txt to parts as text
            set AppleScript's text item delimiters to (ASCII character 10)
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            set txt to parts as text
            set AppleScript's text item delimiters to (ASCII character 13)
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            set txt to parts as text
            set AppleScript's text item delimiters to ""
            return txt
        end sanitise

        tell application "Mail"
            set maxCount to \(limit)
            set maxAgeDays to \(maxAgeDays)
            set cutoffDate to (current date) - (maxAgeDays * days)
            set outputLines to {}
            set allMessages to (every message of inbox \(readClause))

            repeat with msg in allMessages
                if (count of outputLines) >= maxCount then exit repeat
                set msgDate to date received of msg
                if msgDate < cutoffDate then
                else
                    set msgId to my sanitise(id of msg as text)
                    set msgSender to my sanitise(sender of msg as text)
                    set msgSubject to my sanitise(subject of msg as text)
                    try
                        set msgBody to content of msg as text
                        if length of msgBody > 500 then set msgBody to text 1 thru 500 of msgBody
                        set msgBody to my sanitise(msgBody)
                    on error
                        set msgBody to ""
                    end try
                    try
                        set msgDateStr to my sanitise(date received of msg as text)
                    on error
                        set msgDateStr to ""
                    end try
                    set msgRead to read status of msg
                    set msgReadStr to "false"
                    if msgRead then set msgReadStr to "true"
                    set end of outputLines to msgId & (ASCII character 9) & msgSender & (ASCII character 9) & msgSubject & (ASCII character 9) & msgBody & (ASCII character 9) & msgDateStr & (ASCII character 9) & msgReadStr
                end if
            end repeat

            set AppleScript's text item delimiters to (ASCII character 10)
            return (outputLines as text)
        end tell
        """
        return AppleScriptRunner.parseDelimited(
            AppleScriptRunner.run(script, timeout: 60),
            fieldNames: ["id", "sender", "subject", "body_preview", "date", "read"]
        )
    }
}
