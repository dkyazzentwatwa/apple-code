import Foundation

enum ExternalHighlighter {
    case bat
    case chroma
    case pygmentize
}

struct OutputHighlighter {
    static nonisolated(unsafe) var cachedExternal: ExternalHighlighter?
    static nonisolated(unsafe) var checkedExternal = false

    static func render(_ message: String, isTTY: Bool) -> String {
        guard isTTY else { return message }
        return renderMarkdownFences(message)
    }

    private static func renderMarkdownFences(_ message: String) -> String {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var inCode = false
        var lang = ""
        var buffer: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    let code = buffer.joined(separator: "\n")
                    out.append(renderCodeBlock(code: code, language: lang))
                    buffer.removeAll(keepingCapacity: true)
                    inCode = false
                    lang = ""
                } else {
                    inCode = true
                    lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }

            if inCode {
                buffer.append(line)
            } else {
                out.append(line)
            }
        }

        if inCode {
            let code = buffer.joined(separator: "\n")
            out.append(renderCodeBlock(code: code, language: lang))
        }

        return out.joined(separator: "\n")
    }

    private static func renderCodeBlock(code: String, language: String) -> String {
        if let highlighted = highlightWithExternal(code: code, language: language) {
            return "\(TUI.Colors.brightBlack)```\(language)\(TUI.reset)\n\(highlighted)\n\(TUI.Colors.brightBlack)```\(TUI.reset)"
        }

        let lang = language.lowercased()
        let rendered = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { highlightLine(String($0), lang: lang) }
            .joined(separator: "\n")
        return "\(TUI.Colors.brightBlack)```\(language)\(TUI.reset)\n\(rendered)\n\(TUI.Colors.brightBlack)```\(TUI.reset)"
    }

    private static func highlightWithExternal(code: String, language: String) -> String? {
        let engine = detectExternalHighlighter()
        guard let engine else { return nil }

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("apple-code-highlight-\(UUID().uuidString).txt")
        defer { try? fm.removeItem(at: fileURL) }

        do {
            try code.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        let lang = language.isEmpty ? "txt" : language
        switch engine {
        case .bat:
            return runProcess(
                executable: "/usr/bin/env",
                args: ["bat", "--color=always", "--style=plain", "--paging=never", "--language", lang, fileURL.path]
            )
        case .chroma:
            return runProcess(
                executable: "/usr/bin/env",
                args: ["chroma", "-f", "terminal16m", "-l", lang, fileURL.path]
            )
        case .pygmentize:
            return runProcess(
                executable: "/usr/bin/env",
                args: ["pygmentize", "-l", lang, "-f", "terminal256", fileURL.path]
            )
        }
    }

    private static func detectExternalHighlighter() -> ExternalHighlighter? {
        if checkedExternal { return cachedExternal }
        checkedExternal = true

        if commandExists("bat") {
            cachedExternal = .bat
            return cachedExternal
        }
        if commandExists("chroma") {
            cachedExternal = .chroma
            return cachedExternal
        }
        if commandExists("pygmentize") {
            cachedExternal = .pygmentize
            return cachedExternal
        }
        cachedExternal = nil
        return nil
    }

    private static func commandExists(_ command: String) -> Bool {
        guard let out = runProcess(executable: "/usr/bin/env", args: ["which", command]) else { return false }
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func runProcess(executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func highlightLine(_ line: String, lang: String) -> String {
        if isCommentLine(line, lang: lang) {
            return "\(TUI.Colors.brightBlack)\(line)\(TUI.reset)"
        }

        let keywords = keywordSet(lang: lang)
        let chars = Array(line)
        var i = 0
        var result = ""

        while i < chars.count {
            let c = chars[i]

            if c == "\"" || c == "'" {
                let quote = c
                var j = i + 1
                var escaped = false
                while j < chars.count {
                    let cc = chars[j]
                    if escaped {
                        escaped = false
                    } else if cc == "\\" {
                        escaped = true
                    } else if cc == quote {
                        break
                    }
                    j += 1
                }
                let end = min(j, chars.count - 1)
                let token = String(chars[i...end])
                result += "\(TUI.Colors.brightGreen)\(token)\(TUI.reset)"
                i = end + 1
                continue
            }

            if c.isNumber {
                var j = i + 1
                while j < chars.count && (chars[j].isNumber || chars[j] == "." || chars[j] == "_") {
                    j += 1
                }
                let token = String(chars[i..<j])
                result += "\(TUI.Colors.brightCyan)\(token)\(TUI.reset)"
                i = j
                continue
            }

            if c.isLetter || c == "_" {
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") {
                    j += 1
                }
                let token = String(chars[i..<j])
                if keywords.contains(token) {
                    result += "\(TUI.Colors.brightMagenta)\(token)\(TUI.reset)"
                } else {
                    result += "\(TUI.Colors.brightWhite)\(token)\(TUI.reset)"
                }
                i = j
                continue
            }

            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let token = String(chars[i...])
                result += "\(TUI.Colors.brightBlack)\(token)\(TUI.reset)"
                break
            }

            if c == "#" && (lang == "python" || lang == "py" || lang == "bash" || lang == "sh" || lang == "zsh" || lang == "yaml" || lang == "yml") {
                let token = String(chars[i...])
                result += "\(TUI.Colors.brightBlack)\(token)\(TUI.reset)"
                break
            }

            result.append(c)
            i += 1
        }

        return result
    }

    private static func isCommentLine(_ line: String, lang: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("//") { return true }
        if t.hasPrefix("#"), ["python", "py", "bash", "sh", "zsh", "yaml", "yml"].contains(lang) { return true }
        return false
    }

    private static func keywordSet(lang: String) -> Set<String> {
        switch lang {
        case "swift":
            return ["let", "var", "func", "if", "else", "switch", "case", "for", "while", "guard", "return", "struct", "class", "enum", "protocol", "extension", "import", "async", "await", "throws", "try", "do", "catch", "public", "private", "internal", "final", "init"]
        case "javascript", "js", "typescript", "ts":
            return ["const", "let", "var", "function", "if", "else", "switch", "case", "for", "while", "return", "class", "extends", "import", "export", "async", "await", "try", "catch", "throw", "new", "this", "interface", "type"]
        case "python", "py":
            return ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "async", "await", "pass", "break", "continue", "None", "True", "False"]
        case "bash", "sh", "zsh":
            return ["if", "then", "else", "fi", "for", "in", "do", "done", "case", "esac", "function", "local", "export", "return"]
        case "json":
            return ["true", "false", "null"]
        default:
            return ["if", "else", "for", "while", "return", "class", "struct", "function", "import", "from", "let", "var", "const"]
        }
    }
}
