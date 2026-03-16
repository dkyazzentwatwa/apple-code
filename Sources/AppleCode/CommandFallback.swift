import Foundation

private let shellCommandHeads: Set<String> = [
    "git", "ls", "pwd", "cat", "head", "tail", "grep", "rg", "find",
    "swift", "xcodebuild", "npm", "npx", "node", "python", "python3",
    "pip", "pip3", "make", "cmake", "cargo", "docker", "kubectl",
    "whoami", "uname", "ps", "echo", "env", "which", "chmod", "chown",
    "mv", "cp", "ln", "touch", "mkdir", "rmdir", "du", "df"
]

private let placeholderWords: Set<String> = [
    "this", "that", "the", "a", "an", "file", "folder", "directory", "current"
]

private func normalizePromptForExtraction(_ prompt: String) -> String {
    var cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return cleaned }

    let lower = cleaned.lowercased()
    if lower.contains("apple-code") {
        if let marker = cleaned.lastIndex(of: "›") {
            cleaned = String(cleaned[cleaned.index(after: marker)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let marker = cleaned.lastIndex(of: ">") {
            cleaned = String(cleaned[cleaned.index(after: marker)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    return cleaned
}

private func firstToken(in text: String) -> String? {
    text.split(whereSeparator: \.isWhitespace).first.map(String.init)
}

private func looksLikeRawShellCommand(_ prompt: String) -> Bool {
    let cleaned = normalizePromptForExtraction(prompt)
    guard !cleaned.isEmpty, !cleaned.contains("\n") else { return false }

    if cleaned.hasPrefix("./") || cleaned.hasPrefix("/") {
        return true
    }

    guard let token = firstToken(in: cleaned)?.lowercased() else { return false }
    return shellCommandHeads.contains(token)
}

func isCommandIntentPrompt(_ prompt: String) -> Bool {
    let normalized = normalizePromptForExtraction(prompt)
    let p = normalized.lowercased()
    return p.hasPrefix("run ")
        || p.hasPrefix("execute ")
        || p.contains("run bash command")
        || p.contains("run shell command")
        || p.contains("execute command")
        || p.contains("terminal command")
        || p.contains("bash command")
        || looksLikeRawShellCommand(normalized)
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
        || lower.contains("system tool")
        || lower.contains("system tools")
    return refusalSignal && commandSignal
}

func extractShellCommand(from prompt: String) -> String? {
    let trimmed = normalizePromptForExtraction(prompt)
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
    if looksLikeRawShellCommand(trimmed) {
        return trimmed
    }
    return nil
}

private func looksLikeNullOrThinReply(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "(null)" || lower == "nil" || lower == "none" {
        return true
    }
    if lower.count <= 6 && (lower == "ok" || lower == "okay" || lower == "sure") {
        return true
    }
    return false
}

private func looksLikeLocalToolRefusal(_ text: String) -> Bool {
    let lower = text.lowercased()
    let refusalSignal = lower.contains("can't")
        || lower.contains("cannot")
        || lower.contains("unable")
        || lower.contains("do not")
        || lower.contains("don't")
    let localSignal = lower.contains("system tool")
        || lower.contains("system tools")
        || lower.contains("file")
        || lower.contains("folder")
        || lower.contains("directory")
        || lower.contains("terminal")
        || lower.contains("shell")
    return refusalSignal && localSignal
}

private func isFileReadIntentPrompt(_ prompt: String) -> Bool {
    let lower = normalizePromptForExtraction(prompt).lowercased()
    return lower.contains("read the file")
        || lower.contains("read file")
        || lower.contains("readme")
        || lower.contains("contents of")
        || lower.contains("open file")
        || lower.hasPrefix("cat ")
}

private func normalizePathCandidate(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'`.,;:!?()[]{}"))
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    if placeholderWords.contains(lower) { return nil }
    if lower == "readme" { return "README.md" }
    return trimmed
}

private func extractFilePathForReadIntent(from prompt: String) -> String? {
    let cleaned = normalizePromptForExtraction(prompt)
    let lower = cleaned.lowercased()

    if lower.contains("readme") {
        return "README.md"
    }

    let patterns = [
        #"(?:read|open|show|display|print|cat)\s+(?:the\s+)?(?:file\s+)?["'`]([^"'`\n]+)["'`]"#,
        #"(?:contents?\s+of)\s+["'`]([^"'`\n]+)["'`]"#,
        #"(?:read|open|show|display|print|cat)\s+(?:the\s+)?(?:file\s+)?([A-Za-z0-9_./~\-]+)"#,
        #"(?:contents?\s+of)\s+([A-Za-z0-9_./~\-]+)"#,
    ]

    for pattern in patterns {
        if let candidate = regexCapture(pattern, in: cleaned),
           let normalized = normalizePathCandidate(candidate) {
            return normalized
        }
    }

    return nil
}

private func isDirectoryIntentPrompt(_ prompt: String) -> Bool {
    let lower = normalizePromptForExtraction(prompt).lowercased()
    return lower.contains("folder")
        || lower.contains("directory")
        || lower.contains("list files")
        || lower.contains("what's in")
        || lower.contains("whats in")
        || lower.hasPrefix("ls ")
        || lower == "ls"
}

private func extractDirectoryPath(from prompt: String) -> String? {
    let cleaned = normalizePromptForExtraction(prompt)
    let lower = cleaned.lowercased()
    if lower.contains("this folder")
        || lower.contains("this directory")
        || lower.contains("current folder")
        || lower.contains("current directory") {
        return nil
    }

    let patterns = [
        #"(?:folder|directory)\s+["'`]([^"'`\n]+)["'`]"#,
        #"(?:folder|directory)\s+([A-Za-z0-9_./~\-]+)"#,
        #"(?:in|of)\s+([A-Za-z0-9_./~\-]+)\s+(?:folder|directory)"#,
    ]

    for pattern in patterns {
        if let candidate = regexCapture(pattern, in: cleaned),
           let normalized = normalizePathCandidate(candidate) {
            return normalized
        }
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
    guard ToolSafety.shared.currentPolicy().allowAutomaticFallbackExecution else { return nil }
    let cleanedPrompt = normalizePromptForExtraction(userPrompt)
    guard isCommandIntentPrompt(cleanedPrompt) else { return nil }
    guard looksLikeCommandRefusal(modelReply) || looksLikeNullOrThinReply(modelReply) else { return nil }
    guard let command = extractShellCommand(from: cleanedPrompt), !command.isEmpty else { return nil }

    do {
        let output = try await RunCommandTool().call(arguments: .init(command: command, timeout: min(max(timeoutSeconds, 5), 120)))
        return "Command output (`\(command)`):\n\(output)"
    } catch {
        return "Command fallback failed: \(error.localizedDescription)"
    }
}

func resolveFilesystemRefusalFallback(
    userPrompt: String,
    modelReply: String
) async -> String? {
    guard ToolSafety.shared.currentPolicy().allowAutomaticFallbackExecution else { return nil }
    let cleanedPrompt = normalizePromptForExtraction(userPrompt)
    let readIntent = isFileReadIntentPrompt(cleanedPrompt)
    let dirIntent = isDirectoryIntentPrompt(cleanedPrompt)
    guard readIntent || dirIntent else { return nil }
    guard looksLikeLocalToolRefusal(modelReply)
        || looksLikeCommandRefusal(modelReply)
        || looksLikeNullOrThinReply(modelReply) else { return nil }

    if readIntent, let path = extractFilePathForReadIntent(from: cleanedPrompt) {
        do {
            let output = try await ReadFileTool().call(arguments: .init(path: path))
            return "File content (`\(path)`):\n\(output)"
        } catch {
            return "File fallback failed: \(error.localizedDescription)"
        }
    }

    if dirIntent {
        let path = extractDirectoryPath(from: cleanedPrompt)
        do {
            let output = try await ListDirectoryTool().call(arguments: .init(path: path, recursive: nil))
            let displayPath = path ?? "."
            return "Directory listing (`\(displayPath)`):\n\(output)"
        } catch {
            return "Directory fallback failed: \(error.localizedDescription)"
        }
    }
    return nil
}
