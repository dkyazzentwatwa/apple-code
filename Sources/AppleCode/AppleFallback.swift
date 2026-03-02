import Foundation
import FoundationModels

private func isNoResultsMessage(_ text: String) -> Bool {
    text.lowercased().contains("no results found")
}

func looksLikeAppleAccessRefusal(_ text: String) -> Bool {
    let lower = text.lowercased()
    let refusalSignal = lower.contains("can't access")
        || lower.contains("cannot access")
        || lower.contains("unable to access")
        || lower.contains("can't see")
        || lower.contains("cannot see")
        || lower.contains("unable to see")
        || lower.contains("don't have access")
        || lower.contains("do not have access")
        || lower.contains("can't retrieve")
        || lower.contains("cannot retrieve")
        || lower.contains("unable to retrieve")
        || lower.contains("can't view")
        || lower.contains("cannot view")

    let appSignal = lower.contains("reminder")
        || lower.contains("note")
        || lower.contains("notes")
        || lower.contains("calendar")
        || lower.contains("mail")
        || lower.contains("imessage")
        || lower.contains("messages")
        || lower.contains("inbox")

    return refusalSignal && appSignal
}

func looksLikeAppleThinOrDeflectingReply(_ text: String) -> Bool {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.count > 220 { return false }

    if lower.contains("use the reminders tool")
        || lower.contains("use the calendar tool")
        || lower.contains("use the notes tool")
        || lower.contains("use the mail tool")
        || lower.contains("use the messages tool")
        || lower.contains("having trouble creating")
        || lower.contains("trouble creating the event")
        || lower.contains("verify the date format")
        || lower.contains("system tools:")
        || lower.contains("<executable_end>")
        || (lower.contains("```") && lower.contains("tools"))
        || lower.contains("shorten your prompt")
        || lower.contains("then(function")
        || lower.contains("catch(function") {
        return true
    }

    let hasAppWord = lower.contains("reminder")
        || lower.contains("note")
        || lower.contains("calendar")
        || lower.contains("event")
        || lower.contains("appointment")
        || lower.contains("schedule")
        || lower.contains("mail")
        || lower.contains("notes")
        || lower.contains("message")
    let hasNoDataShape = lower.contains("can't")
        || lower.contains("cannot")
        || lower.contains("unable")
        || lower.contains("don't have")
    return hasAppWord && hasNoDataShape
}

func isAppleIntentPrompt(_ prompt: String) -> Bool {
    let p = prompt.lowercased()
    return p.contains("reminder")
        || p.contains("todo")
        || p.contains("to-do")
        || p.contains("calendar")
        || p.contains("event")
        || p.contains("schedule")
        || p.contains("meeting")
        || p.contains("mail")
        || p.contains("email")
        || p.contains("inbox")
        || p.contains("note")
        || p.contains("imessage")
        || p.contains("messages")
        || p.contains("text message")
}

func looksLikeVeryShortNonAnswer(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count < 2 { return true }
    if trimmed.count > 24 { return false }
    if trimmed.range(of: #"\d"#, options: .regularExpression) != nil { return false }
    let lower = trimmed.lowercased()
    if lower.contains("yes") || lower.contains("no") || lower.contains("no events") {
        return false
    }
    // Tiny non-informative outputs like "ok", "null", "shuk."
    return true
}

private func isExplicitNotesWriteIntent(_ prompt: String) -> Bool {
    let p = prompt.lowercased()
    let hasNotes = p.contains("note") || p.contains("notes")
    let hasWrite = p.contains("create")
        || p.contains("new note")
        || p.contains("new apple note")
        || p.contains("append")
        || p.contains("save")
        || p.contains("store")
        || p.contains("put the output")
        || p.contains("put output")
        || p.contains("write")
    return hasNotes && hasWrite
}

private func looksLikeNotesListReply(_ text: String) -> Bool {
    let lower = text.lowercased()
    guard lower.contains("apple notes:") else { return false }
    if lower.contains("created note") || lower.contains("successfully appended") || lower.contains("here is your note") {
        return false
    }
    let lines = text.components(separatedBy: .newlines)
    let listLikeCount = lines.filter { $0.contains("[") && $0.contains("]") }.count
    return listLikeCount >= 2
}

private func parseCalendarCreateRequest(from prompt: String) -> (title: String, startDate: String)? {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let datePattern = #"\b(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\b"#
    guard let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []),
          let match = dateRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
          let dateRange = Range(match.range(at: 1), in: trimmed) else {
        return nil
    }

    let startDate = String(trimmed[dateRange])
    let lower = trimmed.lowercased()

    let titlePatterns = [
        #"(?:named|called|title[d]?)\s+\"([^\"]+)\""#,
        #"(?:named|called|title[d]?)\s+'([^']+)'"#,
        #"(?:named|called|title[d]?)\s+([^\n\r,]+)$"#
    ]

    for pattern in titlePatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let titleMatch = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
           let titleRange = Range(titleMatch.range(at: 1), in: trimmed) {
            let title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return (title: title, startDate: startDate)
            }
        }
    }

    if lower.contains("create") || lower.contains("add") || lower.contains("new event") {
        return (title: "New Event", startDate: startDate)
    }

    return nil
}

private struct ParsedNotesRequest {
    let action: String
    let query: String?
    let body: String?
    let explicitWrite: Bool
}

private func firstRegexCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func parseNotesRequest(from prompt: String) -> ParsedNotesRequest? {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    let hasNotesIntent = lower.contains("note") || lower.contains("notes")
    guard hasNotesIntent else { return nil }

    if (lower.contains("list") || lower.contains("show")) && lower.contains("folder") {
        return ParsedNotesRequest(action: "list_folders", query: nil, body: nil, explicitWrite: false)
    }

    if lower.contains("search") {
        let query = firstRegexCapture(#"(?:search(?:\s+my)?\s+notes?\s+(?:for|about)\s+)(.+)$"#, in: trimmed)
            ?? firstRegexCapture(#"(?:search\s+for\s+)(.+)$"#, in: trimmed)
        return ParsedNotesRequest(action: "search", query: query, body: nil, explicitWrite: false)
    }

    let wantsContent = lower.contains("get content")
        || lower.contains("show content")
        || lower.contains("content of note")
        || lower.contains("read note")
        || lower.contains("open note")
    if wantsContent {
        let query = firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+\"([^\"]+)\")"#, in: trimmed)
            ?? firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+'([^']+)')"#, in: trimmed)
            ?? firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+)(.+)$"#, in: trimmed)
            ?? firstRegexCapture(#"(?:content of note\s+)(.+)$"#, in: trimmed)
        return ParsedNotesRequest(action: "get_content", query: query, body: nil, explicitWrite: false)
    }

    let wantsAppend = lower.contains("append") || (lower.contains("add") && lower.contains("to note"))
    if wantsAppend {
        let noteName = firstRegexCapture(#"(?:to\s+note\s+(?:named|called|titled)\s+\"([^\"]+)\")"#, in: trimmed)
            ?? firstRegexCapture(#"(?:to\s+note\s+(?:named|called|titled)\s+'([^']+)')"#, in: trimmed)
            ?? firstRegexCapture(#"(?:to\s+note\s+)(.+)$"#, in: trimmed)
        let body = firstRegexCapture(#"(?:append\s+\"([^\"]+)\"\s+to\s+note)"#, in: trimmed)
            ?? firstRegexCapture(#"(?:append\s+'([^']+)'\s+to\s+note)"#, in: trimmed)
            ?? firstRegexCapture(#"(?:append\s+)(.+?)(?:\s+to\s+note)"#, in: trimmed)
            ?? firstRegexCapture(#"(?:add\s+)(.+?)(?:\s+to\s+note)"#, in: trimmed)
        return ParsedNotesRequest(action: "append", query: noteName, body: body, explicitWrite: true)
    }

    let wantsCreate = lower.contains("create note")
        || lower.contains("create a note")
        || lower.contains("new note")
        || lower.contains("new apple note")
        || lower.contains("add note")
        || lower.contains("put the output in a new")
        || lower.contains("save the output to a new")
        || lower.contains("store the output in a new")
        || (lower.contains("create") && lower.contains("note"))
    if wantsCreate {
        let title = firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+\"([^\"]+)\")"#, in: trimmed)
            ?? firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+'([^']+)')"#, in: trimmed)
            ?? firstRegexCapture(#"(?:note\s+(?:named|called|titled)\s+)(.+?)(?:\s+with\s+body|\s+body:|$)"#, in: trimmed)
            ?? "New Note"
        let body = firstRegexCapture(#"(?:with\s+body\s+\"([^\"]+)\")"#, in: trimmed)
            ?? firstRegexCapture(#"(?:with\s+body\s+'([^']+)')"#, in: trimmed)
            ?? firstRegexCapture(#"(?:with\s+body\s+)(.+)$"#, in: trimmed)
            ?? firstRegexCapture(#"(?:body:\s+)(.+)$"#, in: trimmed)
        return ParsedNotesRequest(action: "create", query: title, body: body, explicitWrite: true)
    }

    return ParsedNotesRequest(action: "list", query: nil, body: nil, explicitWrite: false)
}

private func parseGenerateToNewNoteRequest(from prompt: String) -> String? {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^(.*?)(?:\s+and\s+|\s+then\s+)?(?:put|save|store|write)\s+(?:the\s+output|this|that|it)\s+(?:in|into|to)\s+(?:a\s+)?new(?:\s+apple)?\s+note(?:\b.*)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
          let range = Range(match.range(at: 1), in: trimmed) else {
        return nil
    }
    let task = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    return task.isEmpty ? nil : task
}

private func generateNoteBody(for taskPrompt: String) async -> String? {
    let instructions = """
    You are a concise assistant.
    Return only the requested content as plain text. No preface.
    """
    let session = LanguageModelSession(instructions: instructions)
    do {
        let response = try await session.respond(to: taskPrompt)
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    } catch {
        return nil
    }
}

private func looksLikeNoteCreationSuccess(_ text: String) -> Bool {
    let lower = text.lowercased()
    return (lower.contains("created note") || lower.contains("successfully created"))
        && lower.contains("note")
}

func resolveNotesComposeFallback(
    userPrompt: String,
    modelReply: String
) async -> String? {
    guard let taskPrompt = parseGenerateToNewNoteRequest(from: userPrompt) else { return nil }
    if looksLikeNoteCreationSuccess(modelReply) { return nil }

    let lower = modelReply.lowercased()
    let isNamePrompt = lower.contains("what would you like to name the note")
    let unusableReply = looksLikeNotesListReply(modelReply)
        || isNamePrompt
        || looksLikeAppleAccessRefusal(modelReply)

    var noteBody: String?
    if !unusableReply {
        let candidate = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.count >= 40 {
            noteBody = candidate
        }
    }
    if noteBody == nil {
        noteBody = await generateNoteBody(for: taskPrompt)
    }
    guard let body = noteBody, !body.isEmpty else {
        return "Apple Notes:\nCould not generate note content to save."
    }

    let title = String(taskPrompt.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    do {
        let output = try await NotesTool().call(arguments: .init(action: "create", query: title, body: body))
        return "Apple Notes:\n\(output)"
    } catch {
        return "Apple Notes:\nFailed to create note: \(error.localizedDescription)"
    }
}

func resolveAppleRefusalFallback(
    userPrompt: String,
    modelReply: String
) async -> String? {
    let appleIntent = isAppleIntentPrompt(userPrompt)
    let shouldFallback = looksLikeAppleAccessRefusal(modelReply)
        || (appleIntent && looksLikeAppleThinOrDeflectingReply(modelReply))
        || (appleIntent && looksLikeVeryShortNonAnswer(modelReply))
        || (isExplicitNotesWriteIntent(userPrompt) && looksLikeNotesListReply(modelReply))
    guard shouldFallback else { return nil }

    return await resolveAppleIntentDirect(userPrompt: userPrompt)
}

func resolveAppleIntentDirect(userPrompt: String) async -> String? {
    let p = userPrompt.lowercased()

    do {
        if p.contains("reminder") || p.contains("todo") || p.contains("to-do") {
            let output = try await RemindersTool().call(arguments: .init(action: "list", query: nil, list: nil))
            if isNoResultsMessage(output) {
                let lists = try await RemindersTool().call(arguments: .init(action: "list_lists", query: nil, list: nil))
                return "Apple Reminders:\nNo incomplete reminders found.\nLists:\n\(lists)"
            }
            return "Apple Reminders:\n\(output)"
        }
        if p.contains("calendar") || p.contains("event") || p.contains("schedule") || p.contains("meeting") {
            if let req = parseCalendarCreateRequest(from: userPrompt),
               (p.contains("create") || p.contains("add") || p.contains("new")) {
                let created = try await CalendarTool().call(arguments: .init(action: "create", query: req.title, startDate: req.startDate))
                return "Apple Calendar:\n\(created)"
            }
            let output = try await CalendarTool().call(arguments: .init(action: "list_events", query: nil, startDate: nil))
            if isNoResultsMessage(output) {
                let calendars = try await CalendarTool().call(arguments: .init(action: "list_calendars", query: nil, startDate: nil))
                return "Apple Calendar:\nNo upcoming events found.\nCalendars:\n\(calendars)"
            }
            return "Apple Calendar:\n\(output)"
        }
        if p.contains("mail") || p.contains("email") || p.contains("inbox") || p.contains("unread") {
            let output = try await MailTool().call(arguments: .init(action: "list_unread", query: nil))
            if isNoResultsMessage(output) {
                return "Apple Mail:\nNo unread messages found."
            }
            return "Apple Mail:\n\(output)"
        }
        if p.contains("note") {
            let parsed = parseNotesRequest(from: userPrompt) ?? ParsedNotesRequest(action: "list", query: nil, body: nil, explicitWrite: false)
            switch parsed.action {
            case "list_folders":
                let folders = try await NotesTool().call(arguments: .init(action: "list_folders", query: nil, body: nil))
                return "Apple Notes:\n\(folders)"
            case "search":
                let query = parsed.query ?? ""
                let output = try await NotesTool().call(arguments: .init(action: "search", query: query, body: nil))
                if isNoResultsMessage(output) {
                    return "Apple Notes:\nNo notes matched '\(query)'."
                }
                return "Apple Notes:\n\(output)"
            case "get_content":
                let target = parsed.query ?? ""
                let output = try await NotesTool().call(arguments: .init(action: "get_content", query: target, body: nil))
                return "Apple Notes:\n\(output)"
            case "create":
                guard parsed.explicitWrite else {
                    return "Apple Notes:\nWrite action skipped because create intent was not explicit."
                }
                var title = parsed.query ?? "New Note"
                var body = parsed.body ?? ""
                if body.isEmpty, let task = parseGenerateToNewNoteRequest(from: userPrompt) {
                    if let generated = await generateNoteBody(for: task) {
                        body = generated
                    }
                    if parsed.query == nil {
                        title = String(task.prefix(80))
                    }
                }
                let output = try await NotesTool().call(arguments: .init(action: "create", query: title, body: body))
                return "Apple Notes:\n\(output)"
            case "append":
                guard parsed.explicitWrite, let noteName = parsed.query, let body = parsed.body else {
                    return "Apple Notes:\nTo append, specify both note name and text to append."
                }
                let output = try await NotesTool().call(arguments: .init(action: "append", query: noteName, body: body))
                return "Apple Notes:\n\(output)"
            default:
                let output = try await NotesTool().call(arguments: .init(action: "list", query: nil, body: nil))
                if isNoResultsMessage(output) {
                    let folders = try await NotesTool().call(arguments: .init(action: "list_folders", query: nil, body: nil))
                    return "Apple Notes:\nNo notes found in the current view.\nFolders:\n\(folders)"
                }
                return "Apple Notes:\n\(output)"
            }
        }
        if p.contains("imessage") || p.contains("message") || p.contains("sms") || p.contains("text") {
            let output = try await MessagesTool().call(arguments: .init(action: "list_recent_chats", query: nil))
            if isNoResultsMessage(output) {
                return "Apple Messages:\nNo recent chats found."
            }
            return "Apple Messages:\n\(output)"
        }
    } catch {
        return "I tried an Apple app tool directly but it failed: \(error.localizedDescription)"
    }

    return nil
}
