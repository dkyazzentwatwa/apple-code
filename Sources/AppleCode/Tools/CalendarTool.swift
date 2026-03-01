import Foundation
import FoundationModels

struct CalendarTool: Tool {
    let name = "calendar"
    let description = "Apple Calendar: list_calendars, list_events, search, create"

    @Generable
    struct Arguments {
        @Guide(description: "Action name")
        let action: String
        @Guide(description: "Search query or event title")
        let query: String?
        @Guide(description: "Start date as YYYY-MM-DD HH:MM")
        let startDate: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list_calendars":
            return listCalendars()
        case "list_events":
            return listEvents(calendar: nil, daysAhead: 7)
        case "search":
            guard let query = arguments.query else {
                return "Error: 'query' is required for search"
            }
            return search(query: query, calendar: nil)
        case "create":
            guard let query = arguments.query, let startDate = arguments.startDate else {
                return "Error: 'query' (title) and 'startDate' are required for create"
            }
            return create(title: query, startDate: startDate, endDate: nil, notes: nil, calendar: nil)
        default:
            return "Unknown action: \(arguments.action). Available: list_calendars, list_events, search, create"
        }
    }

    // MARK: - Actions

    private func listCalendars() -> String {
        let script = """
        tell application "Calendar"
            set calNames to {}
            repeat with cal in every calendar
                set end of calNames to name of cal as text
            end repeat
            set AppleScript's text item delimiters to "|||"
            return calNames as text
        end tell
        """
        guard let raw = AppleScriptRunner.run(script) else {
            return "Error: Could not list calendars"
        }
        if raw.isEmpty { return "No calendars found." }
        let cals = raw.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cals.joined(separator: "\n")
    }

    private func listEvents(calendar: String?, daysAhead: Int, limit: Int = 20) -> String {
        let records = fetchRaw(calendar: calendar, daysAhead: daysAhead, limit: limit)
        return AppleScriptRunner.formatRecords(records) { r in
            "\(r["start_date"] ?? "")  \(r["summary"] ?? "")  [\(r["calendar"] ?? "")]"
        }
    }

    private func search(query: String, calendar: String?, limit: Int = 20) -> String {
        let allEvents = fetchRaw(calendar: calendar, daysAhead: 90, limit: 200)
        let q = query.lowercased()
        let matches = allEvents.filter { e in
            (e["summary"] ?? "").lowercased().contains(q) ||
            (e["description"] ?? "").lowercased().contains(q)
        }.prefix(limit)
        return AppleScriptRunner.formatRecords(Array(matches)) { r in
            "\(r["start_date"] ?? "")  \(r["summary"] ?? "")"
        }
    }

    private func create(title: String, startDate: String, endDate: String?, notes: String?, calendar: String?) -> String {
        let escTitle = AppleScriptRunner.escape(title)

        guard let startAS = dateToAppleScript(startDate) else {
            return "Error: Cannot parse start date '\(startDate)'. Use format: YYYY-MM-DD HH:MM"
        }

        let calClause: String
        if let cal = calendar {
            let escCal = AppleScriptRunner.escape(cal)
            calClause = "set targetCal to calendar \"\(escCal)\""
        } else {
            calClause = "set targetCal to default calendar"
        }

        let notesClause: String
        if let notes = notes {
            let escNotes = AppleScriptRunner.escape(notes)
            notesClause = "set description of newEvent to \"\(escNotes)\""
        } else {
            notesClause = ""
        }

        let endDateSetup: String
        if let endDate = endDate {
            guard let endAS = dateToAppleScript(endDate) else {
                return "Error: Cannot parse end date '\(endDate)'. Use format: YYYY-MM-DD HH:MM"
            }
            endDateSetup = "set endDateVal to \(endAS)"
        } else {
            endDateSetup = "set endDateVal to startDate + (1 * hours)"
        }

        let script = """
        tell application "Calendar"
            try
                \(calClause)
            on error
                return "error: calendar not found"
            end try
            try
                set startDate to \(startAS)
                \(endDateSetup)
                set newEvent to make new event at targetCal with properties {summary:"\(escTitle)", start date:startDate, end date:endDateVal}
                \(notesClause)
                return uid of newEvent as text
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """

        let result = AppleScriptRunner.run(script, timeout: 30)
        if let r = result, !r.hasPrefix("error:") {
            return "Created event '\(title)' (uid: \(r))"
        }
        return "Error creating event: \(result ?? "unknown")"
    }

    // MARK: - Helpers

    private func dateToAppleScript(_ dateStr: String) -> String? {
        let parts = dateStr.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        guard let datePart = parts.first else { return nil }
        let datePieces = datePart.components(separatedBy: "-")
        guard datePieces.count == 3,
              let year = Int(datePieces[0]),
              let month = Int(datePieces[1]),
              let day = Int(datePieces[2]) else { return nil }

        let monthNames = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]
        guard month >= 1, month <= 12 else { return nil }
        let monthName = monthNames[month - 1]

        var hour = 9, minute = 0
        if parts.count >= 2 {
            let timePieces = parts[1].components(separatedBy: ":")
            if timePieces.count >= 2 {
                hour = Int(timePieces[0]) ?? 9
                minute = Int(timePieces[1]) ?? 0
            }
        }

        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "date \"\(monthName) \(day), \(year) \(h12):\(String(format: "%02d", minute)):00 \(ampm)\""
    }

    // MARK: - Internal fetch

    private func fetchRaw(calendar: String?, daysAhead: Int, limit: Int) -> [[String: String]] {
        let fetchBlock: String
        if let cal = calendar {
            let escCal = cal.replacingOccurrences(of: "\"", with: "\\\"")
            fetchBlock = """
                try
                    set targetCal to calendar "\(escCal)"
                on error
                    return ""
                end try
                set allEvents to (every event of targetCal whose start date >= nowDate and start date <= futureDate)
            """
        } else {
            fetchBlock = """
                set allEvents to {}
                repeat with cal in every calendar
                    set allEvents to allEvents & (every event of cal whose start date >= nowDate and start date <= futureDate)
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

        tell application "Calendar"
            set maxCount to \(limit)
            set outputLines to {}
            set nowDate to current date
            set futureDate to nowDate + (\(daysAhead) * days)
            \(fetchBlock)

            repeat with evt in allEvents
                if (count of outputLines) >= maxCount then exit repeat
                set evtId to my sanitise(uid of evt as text)
                set evtSummary to my sanitise(summary of evt as text)
                try
                    set evtDescription to description of evt as text
                    if length of evtDescription > 400 then set evtDescription to text 1 thru 400 of evtDescription
                    set evtDescription to my sanitise(evtDescription)
                on error
                    set evtDescription to ""
                end try
                try
                    set evtStart to my sanitise(start date of evt as text)
                on error
                    set evtStart to ""
                end try
                try
                    set evtEnd to my sanitise(end date of evt as text)
                on error
                    set evtEnd to ""
                end try
                try
                    set evtCal to my sanitise(name of calendar of evt as text)
                on error
                    set evtCal to ""
                end try
                set end of outputLines to evtId & (ASCII character 9) & evtSummary & (ASCII character 9) & evtDescription & (ASCII character 9) & evtStart & (ASCII character 9) & evtEnd & (ASCII character 9) & evtCal
            end repeat

            set AppleScript's text item delimiters to (ASCII character 10)
            return (outputLines as text)
        end tell
        """
        return AppleScriptRunner.parseDelimited(
            AppleScriptRunner.run(script, timeout: 60),
            fieldNames: ["id", "summary", "description", "start_date", "end_date", "calendar"]
        )
    }
}
