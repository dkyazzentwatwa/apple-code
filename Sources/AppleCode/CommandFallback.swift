import Foundation

func isCommandIntentPrompt(_ prompt: String) -> Bool {
    let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return p.hasPrefix("run ")
        || p.hasPrefix("execute ")
        || p.contains("run bash command")
        || p.contains("run shell command")
        || p.contains("execute command")
        || p.contains("terminal command")
        || p.contains("bash command")
}

func looksLikeCommandRefusal(_ text: String) -> Bool {
    let lower = text.lowercased()
    let refusalSignal = lower.contains("can't")
        || lower.contains("cannot")
        || lower.contains("unable")
        || lower.contains("do not")
        || lower.contains("don't")
    let commandSignal = lower.contains("run shell command")
        || lower.contains("run shell commands")
        || lower.contains("run commands")
        || lower.contains("execute command")
        || lower.contains("bash command")
        || lower.contains("terminal command")
        || lower.contains("cannot run")
        || lower.contains("can't run")
    return refusalSignal && commandSignal
}

func extractShellCommand(from prompt: String) -> String? {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    let prefixes = [
        "run bash command ",
        "run shell command ",
        "execute command ",
        "run command ",
        "execute ",
        "run "
    ]

    for prefix in prefixes {
        if lower.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let raw = String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            if !stripped.isEmpty {
                return stripped
            }
        }
    }

    if let cmd = regexCapture(#"`([^`]+)`"#, in: trimmed), !cmd.isEmpty {
        return cmd
    }
    if let cmd = regexCapture(#"\"([^\"]+)\""#, in: trimmed), !cmd.isEmpty {
        return cmd
    }
    return nil
}

private func regexCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

func resolveCommandRefusalFallback(
    userPrompt: String,
    modelReply: String,
    timeoutSeconds: Int
) async -> String? {
    guard isCommandIntentPrompt(userPrompt) else { return nil }
    guard looksLikeCommandRefusal(modelReply) else { return nil }
    guard let command = extractShellCommand(from: userPrompt), !command.isEmpty else { return nil }

    do {
        let output = try await RunCommandTool().call(arguments: .init(command: command, timeout: min(max(timeoutSeconds, 5), 120)))
        return "Command output (`\(command)`):\n\(output)"
    } catch {
        return "Command fallback failed: \(error.localizedDescription)"
    }
}
