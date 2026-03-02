import Foundation

private enum AppleCheckState: String {
    case ok = "OK"
    case blocked = "BLOCKED"
    case error = "ERROR"
}

private struct AppleCheck {
    let name: String
    let state: AppleCheckState
    let detail: String
}

func runAppleToolDiagnostics() async -> String {
    var checks: [AppleCheck] = []

    checks.append(runAppleScriptCountCheck(
        name: "Reminders",
        script: #"tell application "Reminders" to return (count of every list)"#,
        countLabel: "lists"
    ))

    checks.append(runAppleScriptCountCheck(
        name: "Notes",
        script: #"tell application "Notes" to return (count of every folder)"#,
        countLabel: "folders"
    ))

    checks.append(runAppleScriptCountCheck(
        name: "Calendar",
        script: #"tell application "Calendar" to return (count of every calendar)"#,
        countLabel: "calendars"
    ))

    checks.append(runAppleScriptCountCheck(
        name: "Mail",
        script: #"tell application "Mail" to return (count of messages of inbox)"#,
        countLabel: "inbox messages"
    ))

    checks.append(await runMessagesCheck())

    let lines = checks.map { check in
        "- \(check.name): \(check.state.rawValue) — \(check.detail)"
    }.joined(separator: "\n")

    let blockedCount = checks.filter { $0.state == .blocked }.count
    let errorCount = checks.filter { $0.state == .error }.count
    let okCount = checks.filter { $0.state == .ok }.count
    let summary = "Summary: \(okCount) OK, \(blockedCount) BLOCKED, \(errorCount) ERROR"

    return """
    Apple Tool Diagnostics
    \(summary)

    \(lines)
    """
}

private func runAppleScriptCountCheck(
    name: String,
    script: String,
    countLabel: String
) -> AppleCheck {
    let result = AppleScriptRunner.runDetailed(script, timeout: 20)
    if result.succeeded {
        if let count = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return AppleCheck(name: name, state: .ok, detail: "\(countLabel): \(count)")
        }
        if result.stdout.isEmpty {
            return AppleCheck(name: name, state: .ok, detail: "responded with empty output")
        }
        return AppleCheck(name: name, state: .ok, detail: "response: \(result.stdout)")
    }

    let classified = AppleScriptRunner.classifyFailure(result, appName: name)
    let lower = classified.lowercased()
    let state: AppleCheckState = lower.contains("permission")
        || lower.contains("automation")
        || lower.contains("not permitted")
        ? .blocked
        : .error
    return AppleCheck(name: name, state: state, detail: classified)
}

private func runMessagesCheck() async -> AppleCheck {
    do {
        let raw = try await MessagesTool().call(arguments: .init(action: "list_recent_chats", query: nil))
        let lower = raw.lowercased()
        if lower.hasPrefix("error: cannot access messages database") || lower.contains("full disk access") {
            return AppleCheck(
                name: "Messages",
                state: .blocked,
                detail: "Full Disk Access required for Terminal/iTerm (Messages database)."
            )
        }
        if lower.hasPrefix("error:") {
            return AppleCheck(name: "Messages", state: .error, detail: raw)
        }
        if lower.contains("no recent chats found") {
            return AppleCheck(name: "Messages", state: .ok, detail: "recent chats: 0")
        }
        let lineCount = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        return AppleCheck(name: "Messages", state: .ok, detail: "recent chats: \(lineCount)")
    } catch {
        return AppleCheck(name: "Messages", state: .error, detail: error.localizedDescription)
    }
}
