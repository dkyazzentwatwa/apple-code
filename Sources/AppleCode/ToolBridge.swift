import Foundation
import FoundationModels

enum ToolBridge {
    static func toolDefinitions(for tools: [any Tool]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let parameters = schema(for: tool.name) else { return nil }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters,
                ],
            ]
        }
    }

    static func invoke(
        toolName: String,
        argumentsJSON: String,
        availableTools: [any Tool]
    ) async -> String {
        let availableNames = Set(availableTools.map { $0.name })
        guard availableNames.contains(toolName) else {
            return "Error: Tool '\(toolName)' is not available for this request."
        }

        do {
            let args = try parseArgumentsObject(argumentsJSON)
            switch toolName {
            case "readFile":
                let path = try requiredString(args, key: "path")
                return try await ReadFileTool().call(arguments: .init(path: path))

            case "writeFile":
                let path = try requiredString(args, key: "path")
                let content = try requiredString(args, key: "content")
                return try await WriteFileTool().call(arguments: .init(path: path, content: content))

            case "editFile":
                let path = try requiredString(args, key: "path")
                let oldString = try requiredString(args, key: "oldString")
                // newString may be empty (deletion), so don't use requiredString
                let newString = (args["newString"] as? String) ?? ""
                return try await EditFileTool().call(arguments: .init(path: path, oldString: oldString, newString: newString))

            case "listDirectory":
                let path = optionalString(args, key: "path")
                let recursive = optionalBool(args, key: "recursive")
                return try await ListDirectoryTool().call(arguments: .init(path: path, recursive: recursive))

            case "searchFiles":
                let pattern = try requiredString(args, key: "pattern")
                let path = optionalString(args, key: "path")
                return try await SearchFilesTool().call(arguments: .init(pattern: pattern, path: path))

            case "searchContent":
                let pattern = try requiredString(args, key: "pattern")
                let path = optionalString(args, key: "path")
                let filePattern = optionalString(args, key: "filePattern")
                return try await SearchContentTool().call(arguments: .init(pattern: pattern, path: path, filePattern: filePattern))

            case "runCommand":
                let command = try requiredString(args, key: "command")
                let timeout = optionalInt(args, key: "timeout")
                return try await RunCommandTool().call(arguments: .init(command: command, timeout: timeout))

            case "createPDF":
                let path = try requiredString(args, key: "path")
                let title = optionalString(args, key: "title")
                let content = try requiredString(args, key: "content")
                return try await CreatePDFTool().call(arguments: .init(path: path, title: title, content: content))

            case "webSearch":
                let query = try requiredString(args, key: "query")
                let limit = optionalInt(args, key: "limit")
                return try await WebSearchTool().call(arguments: .init(query: query, limit: limit))

            case "webFetch":
                let url = try requiredString(args, key: "url")
                let maxChars = optionalInt(args, key: "maxChars")
                return try await WebFetchTool().call(arguments: .init(url: url, maxChars: maxChars))

            case "agentBrowser":
                let action = try requiredString(args, key: "action")
                let url = optionalString(args, key: "url")
                let selector = optionalString(args, key: "selector")
                let text = optionalString(args, key: "text")
                let key = optionalString(args, key: "key")
                let path = optionalString(args, key: "path")
                let session = optionalString(args, key: "session")
                let timeoutSeconds = optionalInt(args, key: "timeoutSeconds")
                return try await AgentBrowserTool().call(arguments: .init(
                    action: action,
                    url: url,
                    selector: selector,
                    text: text,
                    key: key,
                    path: path,
                    session: session,
                    timeoutSeconds: timeoutSeconds
                ))

            case "notes":
                let action = try requiredString(args, key: "action")
                let query = optionalString(args, key: "query")
                let body = optionalString(args, key: "body")
                return try await NotesTool().call(arguments: .init(action: action, query: query, body: body))

            case "mail":
                let action = try requiredString(args, key: "action")
                let query = optionalString(args, key: "query")
                return try await MailTool().call(arguments: .init(action: action, query: query))

            case "calendar":
                let action = try requiredString(args, key: "action")
                let query = optionalString(args, key: "query")
                let startDate = optionalString(args, key: "startDate")
                return try await CalendarTool().call(arguments: .init(action: action, query: query, startDate: startDate))

            case "reminders":
                let action = try requiredString(args, key: "action")
                let query = optionalString(args, key: "query")
                let list = optionalString(args, key: "list")
                return try await RemindersTool().call(arguments: .init(action: action, query: query, list: list))

            case "messages":
                let action = try requiredString(args, key: "action")
                let query = optionalString(args, key: "query")
                return try await MessagesTool().call(arguments: .init(action: action, query: query))

            case "git":
                let action = try requiredString(args, key: "action")
                let arg = optionalString(args, key: "arg")
                return try await GitTool().call(arguments: .init(action: action, arg: arg))

            default:
                return "Error: Unsupported tool '\(toolName)'."
            }
        } catch {
            return "Error invoking tool '\(toolName)': \(error.localizedDescription)"
        }
    }

    private static func parseArgumentsObject(_ json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [:]
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ToolBridgeError.invalidArguments
        }
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = decoded as? [String: Any] else {
            throw ToolBridgeError.argumentsMustBeObject
        }
        return object
    }

    private static func requiredString(_ args: [String: Any], key: String) throws -> String {
        guard let value = optionalString(args, key: key) else {
            throw ToolBridgeError.missingRequiredField(key)
        }
        return value
    }

    private static func optionalString(_ args: [String: Any], key: String) -> String? {
        guard let raw = args[key] else { return nil }
        if raw is NSNull { return nil }
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let num = raw as? NSNumber {
            return num.stringValue
        }
        return nil
    }

    private static func optionalInt(_ args: [String: Any], key: String) -> Int? {
        guard let raw = args[key] else { return nil }
        if raw is NSNull { return nil }
        if let intValue = raw as? Int {
            return intValue
        }
        if let doubleValue = raw as? Double {
            return Int(doubleValue)
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let text = raw as? String, let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return nil
    }

    private static func optionalBool(_ args: [String: Any], key: String) -> Bool? {
        guard let raw = args[key] else { return nil }
        if raw is NSNull { return nil }
        if let boolValue = raw as? Bool {
            return boolValue
        }
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        if let text = raw as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y", "on"].contains(normalized) {
                return true
            }
            if ["false", "0", "no", "n", "off"].contains(normalized) {
                return false
            }
        }
        return nil
    }

    private static func schema(for toolName: String) -> [String: Any]? {
        switch toolName {
        case "readFile":
            return schemaObject(
                properties: [
                    "path": stringProperty("File path"),
                ],
                required: ["path"]
            )
        case "writeFile":
            return schemaObject(
                properties: [
                    "path": stringProperty("File path"),
                    "content": stringProperty("File content"),
                ],
                required: ["path", "content"]
            )
        case "editFile":
            return schemaObject(
                properties: [
                    "path": stringProperty("File path"),
                    "oldString": stringProperty("Exact string to find (must appear exactly once)"),
                    "newString": stringProperty("Replacement string"),
                ],
                required: ["path", "oldString", "newString"]
            )
        case "listDirectory":
            return schemaObject(
                properties: [
                    "path": stringProperty("Directory path"),
                    "recursive": boolProperty("Recurse into subdirectories"),
                ],
                required: []
            )
        case "searchFiles":
            return schemaObject(
                properties: [
                    "pattern": stringProperty("Glob pattern like *.swift"),
                    "path": stringProperty("Search directory"),
                ],
                required: ["pattern"]
            )
        case "searchContent":
            return schemaObject(
                properties: [
                    "pattern": stringProperty("Search text"),
                    "path": stringProperty("Search directory"),
                    "filePattern": stringProperty("File filter like *.swift"),
                ],
                required: ["pattern"]
            )
        case "runCommand":
            return schemaObject(
                properties: [
                    "command": stringProperty("Shell command"),
                    "timeout": intProperty("Timeout in seconds"),
                ],
                required: ["command"]
            )
        case "createPDF":
            return schemaObject(
                properties: [
                    "path": stringProperty("Output PDF file path"),
                    "title": stringProperty("PDF title"),
                    "content": stringProperty("Main text content"),
                ],
                required: ["path", "content"]
            )
        case "webSearch":
            return schemaObject(
                properties: [
                    "query": stringProperty("Search query"),
                    "limit": intProperty("Result count"),
                ],
                required: ["query"]
            )
        case "webFetch":
            return schemaObject(
                properties: [
                    "url": stringProperty("HTTP or HTTPS URL"),
                    "maxChars": intProperty("Maximum characters in output"),
                ],
                required: ["url"]
            )
        case "agentBrowser":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action: open, snapshot, click, fill, type, press, wait, get_text, get_url, get_title, screenshot, close"),
                    "url": stringProperty("URL for open"),
                    "selector": stringProperty("Selector or @ref"),
                    "text": stringProperty("Input text"),
                    "key": stringProperty("Keyboard key"),
                    "path": stringProperty("Screenshot path"),
                    "session": stringProperty("Browser session name"),
                    "timeoutSeconds": intProperty("Timeout in seconds"),
                ],
                required: ["action"]
            )
        case "notes":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action name"),
                    "query": stringProperty("Title, name, or search query"),
                    "body": stringProperty("Body or text content"),
                ],
                required: ["action"]
            )
        case "mail":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action name"),
                    "query": stringProperty("Query or message ID"),
                ],
                required: ["action"]
            )
        case "calendar":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action name"),
                    "query": stringProperty("Search query or event title"),
                    "startDate": stringProperty("Start date as YYYY-MM-DD HH:MM"),
                ],
                required: ["action"]
            )
        case "reminders":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action name"),
                    "query": stringProperty("Search query, reminder name, or ID"),
                    "list": stringProperty("Reminders list name"),
                ],
                required: ["action"]
            )
        case "messages":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action name"),
                    "query": stringProperty("Search text"),
                ],
                required: ["action"]
            )
        case "git":
            return schemaObject(
                properties: [
                    "action": stringProperty("Action: status | diff | log | commit | stash | branch_list | blame"),
                    "arg": stringProperty("File path for blame, commit message for commit, or stash op (push/pop/list)"),
                ],
                required: ["action"]
            )
        default:
            return nil
        }
    }

    private static func schemaObject(
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false,
        ]
    }

    private static func stringProperty(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func intProperty(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static func boolProperty(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private enum ToolBridgeError: LocalizedError {
        case invalidArguments
        case argumentsMustBeObject
        case missingRequiredField(String)

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                return "Invalid tool arguments payload."
            case .argumentsMustBeObject:
                return "Tool arguments must be a JSON object."
            case .missingRequiredField(let key):
                return "Missing required tool argument: \(key)"
            }
        }
    }
}
