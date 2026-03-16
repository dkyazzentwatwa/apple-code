import Foundation
import FoundationModels

struct RemindersTool: Tool {
    let name = "reminders"
    let description = "Apple Reminders: list_lists, list, search, create, complete"

    @Generable
    struct Arguments {
        @Guide(description: "Action name")
        let action: String
        @Guide(description: "Search query, reminder name, or ID")
        let query: String?
        @Guide(description: "Reminders list name")
        let list: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let policy = ToolSafety.shared.currentPolicy()
        switch arguments.action {
        case "list_lists":
            return listLists()
        case "list":
            return list(listName: arguments.query ?? arguments.list, filter: "incomplete")
        case "search":
            guard let query = arguments.query else {
                return "Error: 'query' is required for search"
            }
            return search(query: query, listName: arguments.list)
        case "create":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Reminders create is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let query = arguments.query else {
                return "Error: 'query' (reminder name) is required for create"
            }
            return create(name: query, listName: arguments.list ?? "Reminders", notes: nil, dueDate: nil)
        case "complete":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Reminders complete is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let query = arguments.query, let list = arguments.list else {
                return "Error: 'query' (reminder ID) and 'list' are required for complete"
            }
            return complete(reminderId: query, listName: list)
        default:
            return "Unknown action: \(arguments.action). Available: list_lists, list, search, create, complete"
        }
    }

    // MARK: - Actions

    private func listLists() -> String {
        let script = """
        tell application "Reminders"
            set listNames to {}
            repeat with lst in every list
                set end of listNames to name of lst as text
            end repeat
            set AppleScript's text item delimiters to "|||"
            return listNames as text
        end tell
        """
        guard let raw = AppleScriptRunner.run(script) else {
            return "Error: Could not list reminder lists"
        }
        if raw.isEmpty { return "No reminder lists found." }
        let lists = raw.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lists.joined(separator: "\n")
    }

    private func list(listName: String?, filter: String, limit: Int = 50) -> String {
        let records = fetchRaw(listName: listName, filterCompleted: filter, limit: limit)
        return AppleScriptRunner.formatRecords(records) { r in
            let due = r["due_date"].flatMap { $0.isEmpty ? nil : "  [due: \($0)]" } ?? ""
            let status = r["completed"] == "true" ? " (done)" : ""
            return "\(r["name"] ?? "")\(due)\(status)  [\(r["list"] ?? "")]"
        }
    }

    private func search(query: String, listName: String?, limit: Int = 20) -> String {
        let allReminders = fetchRaw(listName: listName, filterCompleted: "all", limit: 200)
        let q = query.lowercased()
        let matches = allReminders.filter { r in
            (r["name"] ?? "").lowercased().contains(q) ||
            (r["body"] ?? "").lowercased().contains(q)
        }.prefix(limit)
        return AppleScriptRunner.formatRecords(Array(matches)) { r in
            let due = r["due_date"].flatMap { $0.isEmpty ? nil : "  [due: \($0)]" } ?? ""
            return "\(r["name"] ?? "")\(due)"
        }
    }

    private func create(name: String, listName: String, notes: String?, dueDate: String?) -> String {
        let escName = AppleScriptRunner.escape(name)
        let escList = AppleScriptRunner.escape(listName)

        var propsParts = ["name:\"\(escName)\""]
        if let notes = notes {
            let escNotes = AppleScriptRunner.escape(notes)
            propsParts.append("body:\"\(escNotes)\"")
        }
        let props = "{\(propsParts.joined(separator: ", "))}"

        let dueClause: String
        if let dueDate = dueDate {
            let escDue = AppleScriptRunner.escape(dueDate)
            dueClause = "set due date of newRem to date \"\(escDue)\""
        } else {
            dueClause = ""
        }

        let script = """
        tell application "Reminders"
            try
                set targetList to list "\(escList)"
            on error
                return "error: list not found"
            end try
            try
                set newRem to make new reminder at targetList with properties \(props)
                \(dueClause)
                return id of newRem as text
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        let result = AppleScriptRunner.run(script, timeout: 30)
        if let r = result, !r.hasPrefix("error:") {
            return "Created reminder '\(name)' (id: \(r))"
        }
        return "Error creating reminder: \(result ?? "unknown")"
    }

    private func complete(reminderId: String, listName: String) -> String {
        let escId = reminderId.replacingOccurrences(of: "\"", with: "\\\"")
        let escList = listName.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Reminders"
            try
                set targetList to list "\(escList)"
                set matchedRem to first reminder of targetList whose id as text is "\(escId)"
                set completed of matchedRem to true
                return "ok"
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        let result = AppleScriptRunner.run(script, timeout: 30)
        return result == "ok" ? "Reminder marked as completed." : "Error: \(result ?? "unknown")"
    }

    // MARK: - Internal fetch

    private func fetchRaw(listName: String?, filterCompleted: String, limit: Int) -> [[String: String]] {
        let completionClause: String
        switch filterCompleted {
        case "incomplete": completionClause = "whose completed is false"
        case "complete": completionClause = "whose completed is true"
        default: completionClause = ""
        }

        let fetchBlock: String
        if let listName = listName {
            let escList = listName.replacingOccurrences(of: "\"", with: "\\\"")
            fetchBlock = """
                try
                    set targetList to list "\(escList)"
                on error
                    return ""
                end try
                set allReminders to (every reminder of targetList \(completionClause))
            """
        } else {
            fetchBlock = """
                set allReminders to {}
                repeat with lst in every list
                    set allReminders to allReminders & (every reminder of lst \(completionClause))
                end repeat
            """
        }

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

        tell application "Reminders"
            set maxCount to \(limit)
            set outputLines to {}
            \(fetchBlock)

            repeat with rem in allReminders
                if (count of outputLines) >= maxCount then exit repeat
                set remId to my sanitise(id of rem as text)
                set remName to my sanitise(name of rem as text)
                try
                    set remBody to body of rem as text
                    if length of remBody > 400 then set remBody to text 1 thru 400 of remBody
                    set remBody to my sanitise(remBody)
                on error
                    set remBody to ""
                end try
                try
                    set remDue to my sanitise(due date of rem as text)
                on error
                    set remDue to ""
                end try
                set remCompleted to completed of rem
                set remCompletedStr to "false"
                if remCompleted then set remCompletedStr to "true"
                try
                    set remList to my sanitise(name of container of rem as text)
                on error
                    set remList to ""
                end try
                set end of outputLines to remId & (ASCII character 9) & remName & (ASCII character 9) & remBody & (ASCII character 9) & remDue & (ASCII character 9) & remCompletedStr & (ASCII character 9) & remList
            end repeat

            set AppleScript's text item delimiters to (ASCII character 10)
            return (outputLines as text)
        end tell
        """
        return AppleScriptRunner.parseDelimited(
            AppleScriptRunner.run(script, timeout: 60),
            fieldNames: ["id", "name", "body", "due_date", "completed", "list"]
        )
    }
}
