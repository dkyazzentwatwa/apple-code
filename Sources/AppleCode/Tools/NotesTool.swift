import Foundation
import FoundationModels

struct NotesTool: Tool {
    let name = "notes"
    let description = "Apple Notes: list_folders, list, search, get_content, create, append"

    @Generable
    struct Arguments {
        @Guide(description: "Action name")
        let action: String
        @Guide(description: "Title, name, or search query")
        let query: String?
        @Guide(description: "Body or text content")
        let body: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case "list_folders":
            return listFolders()
        case "list":
            return list(folder: arguments.query)
        case "search":
            guard let query = arguments.query else {
                return "Error: 'query' is required for search"
            }
            return search(query: query, folder: nil)
        case "get_content":
            guard let query = arguments.query else {
                return "Error: 'query' (note name or id) is required for get_content"
            }
            return getContent(nameOrId: query, folder: nil)
        case "create":
            guard let query = arguments.query else {
                return "Error: 'query' (title) is required for create"
            }
            return create(title: query, body: arguments.body ?? "", folder: nil)
        case "append":
            guard let query = arguments.query, let body = arguments.body else {
                return "Error: 'query' (note name) and 'body' (text) are required for append"
            }
            return append(nameOrId: query, text: body, folder: nil)
        default:
            return "Unknown action: \(arguments.action). Available: list_folders, list, search, get_content, create, append"
        }
    }

    // MARK: - Actions

    private func listFolders() -> String {
        let script = """
        tell application "Notes"
            set folderNames to {}
            repeat with f in every folder
                set end of folderNames to name of f as text
            end repeat
            set AppleScript's text item delimiters to "|||"
            return folderNames as text
        end tell
        """
        guard let raw = AppleScriptRunner.run(script) else {
            return "Error: Could not list Notes folders"
        }
        if raw.isEmpty { return "No folders found." }
        let folders = raw.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return folders.joined(separator: "\n")
    }

    private func list(folder: String?, limit: Int = 20) -> String {
        let records = fetchRaw(folder: folder, limit: limit)
        return AppleScriptRunner.formatRecords(records) { r in
            "\(r["name"] ?? "")  [\(r["modification_date"] ?? "")]"
        }
    }

    private func search(query: String, folder: String?, limit: Int = 20) -> String {
        let allNotes = fetchRaw(folder: folder, limit: 200)
        let q = query.lowercased()
        let matches = allNotes.filter { n in
            (n["name"] ?? "").lowercased().contains(q) ||
            (n["preview"] ?? "").lowercased().contains(q)
        }.prefix(limit)
        return AppleScriptRunner.formatRecords(Array(matches)) { r in
            "\(r["name"] ?? "")  [\(r["modification_date"] ?? "")]"
        }
    }

    private func getContent(nameOrId: String, folder: String?) -> String {
        let esc = nameOrId.replacingOccurrences(of: "\"", with: "\\\"")
        let findBlock: String
        if let folder = folder {
            let escFolder = folder.replacingOccurrences(of: "\"", with: "\\\"")
            findBlock = """
                try
                    set targetContainer to folder "\(escFolder)"
                on error
                    return ""
                end try
                set matchedNote to missing value
                repeat with n in (every note of targetContainer)
                    if (name of n as text) is "\(esc)" or (id of n as text) is "\(esc)" then
                        set matchedNote to n
                        exit repeat
                    end if
                end repeat
            """
        } else {
            findBlock = """
                set matchedNote to missing value
                repeat with n in (every note)
                    if (name of n as text) is "\(esc)" or (id of n as text) is "\(esc)" then
                        set matchedNote to n
                        exit repeat
                    end if
                end repeat
            """
        }
        let script = """
        tell application "Notes"
            \(findBlock)
            if matchedNote is missing value then return ""
            try
                return plaintext of matchedNote as text
            on error
                return ""
            end try
        end tell
        """
        return AppleScriptRunner.run(script, timeout: 30) ?? "Note not found."
    }

    private func create(title: String, body: String, folder: String?) -> String {
        let et = AppleScriptRunner.escape(title)
        let eb = AppleScriptRunner.escape(body)

        let placement: String
        if let folder = folder {
            let ef = AppleScriptRunner.escape(folder)
            placement = """
                if not (exists folder "\(ef)") then
                    set targetFolder to make new folder with properties {name:"\(ef)"}
                else
                    set targetFolder to folder "\(ef)"
                end if
                set newNote to make new note at targetFolder with properties {name:"\(et)", body:"\(eb)"}
            """
        } else {
            placement = "set newNote to make new note with properties {name:\"\(et)\", body:\"\(eb)\"}"
        }

        let script = """
        tell application "Notes"
            try
                \(placement)
                return id of newNote as text
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        let result = AppleScriptRunner.run(script, timeout: 30)
        if let r = result, !r.hasPrefix("error:") {
            return "Created note '\(title)' (id: \(r))"
        }
        return "Error creating note: \(result ?? "unknown error")"
    }

    private func append(nameOrId: String, text: String, folder: String?) -> String {
        let escName = AppleScriptRunner.escape(nameOrId)
        let escText = AppleScriptRunner.escape(text)

        let findBlock: String
        if let folder = folder {
            let escFolder = AppleScriptRunner.escape(folder)
            findBlock = """
                try
                    set targetContainer to folder "\(escFolder)"
                on error
                    return "error: folder not found"
                end try
                set matchedNote to missing value
                repeat with n in (every note of targetContainer)
                    if (name of n as text) is "\(escName)" or (id of n as text) is "\(escName)" then
                        set matchedNote to n
                        exit repeat
                    end if
                end repeat
            """
        } else {
            findBlock = """
                set matchedNote to missing value
                repeat with n in (every note)
                    if (name of n as text) is "\(escName)" or (id of n as text) is "\(escName)" then
                        set matchedNote to n
                        exit repeat
                    end if
                end repeat
            """
        }

        let script = """
        tell application "Notes"
            \(findBlock)
            if matchedNote is missing value then return "error: note not found"
            try
                set existingBody to plaintext of matchedNote
                set body of matchedNote to existingBody & "\\n\\n" & "\(escText)"
                return "ok"
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        let result = AppleScriptRunner.run(script, timeout: 30)
        return result == "ok" ? "Successfully appended to note." : "Error: \(result ?? "unknown")"
    }

    // MARK: - Internal fetch

    private func fetchRaw(folder: String?, limit: Int) -> [[String: String]] {
        let fetchBlock: String
        if let folder = folder {
            let escFolder = folder.replacingOccurrences(of: "\"", with: "\\\"")
            fetchBlock = """
                try
                    set targetContainer to folder "\(escFolder)"
                on error
                    return ""
                end try
                set allNotes to every note of targetContainer
            """
        } else {
            fetchBlock = "set allNotes to every note"
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

        tell application "Notes"
            set maxCount to \(limit)
            set outputLines to {}
            \(fetchBlock)

            repeat with n in allNotes
                if (count of outputLines) >= maxCount then exit repeat
                set nId to my sanitise(id of n as text)
                set nName to my sanitise(name of n as text)
                try
                    set nBody to plaintext of n as text
                    if length of nBody > 400 then set nBody to text 1 thru 400 of nBody
                    set nBody to my sanitise(nBody)
                on error
                    set nBody to ""
                end try
                try
                    set nModDate to my sanitise(modification date of n as text)
                on error
                    set nModDate to ""
                end try
                set end of outputLines to nId & (ASCII character 9) & nName & (ASCII character 9) & nBody & (ASCII character 9) & nModDate
            end repeat

            set AppleScript's text item delimiters to (ASCII character 10)
            return (outputLines as text)
        end tell
        """
        return AppleScriptRunner.parseDelimited(
            AppleScriptRunner.run(script, timeout: 60),
            fieldNames: ["id", "name", "preview", "modification_date"]
        )
    }
}
