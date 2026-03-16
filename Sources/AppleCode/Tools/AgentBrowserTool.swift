import Foundation
import FoundationModels

struct AgentBrowserTool: Tool {
    let name = "agentBrowser"
    let description = "Control browser automation via agent-browser CLI"

    @Generable
    struct Arguments {
        @Guide(description: "Action: open, snapshot, click, fill, type, press, wait, get_text, get_url, get_title, screenshot, close")
        let action: String
        @Guide(description: "URL for open")
        let url: String?
        @Guide(description: "Selector or @ref for element actions")
        let selector: String?
        @Guide(description: "Input text")
        let text: String?
        @Guide(description: "Keyboard key (Enter, Tab, etc.)")
        let key: String?
        @Guide(description: "Path for screenshot")
        let path: String?
        @Guide(description: "Browser session name")
        let session: String?
        @Guide(description: "Timeout in seconds")
        let timeoutSeconds: Int?
    }

    private static let allowedActions: Set<String> = [
        "open", "snapshot", "click", "fill", "type", "press",
        "wait", "get_text", "get_url", "get_title", "screenshot", "close",
    ]

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.allowedActions.contains(action) else {
            return "Error: Unsupported action '\(arguments.action)'. Allowed: \(Self.allowedActions.sorted().joined(separator: ", "))"
        }
        let policy = ToolSafety.shared.currentPolicy()

        let timeoutSeconds = max(1, min(arguments.timeoutSeconds ?? 30, 120))
        let sessionName = normalizedSessionName(arguments.session)

        guard let executablePath = resolveExecutable("agent-browser") else {
            return "Error: agent-browser is not installed or not in PATH."
        }

        var commandArgs = ["--session", sessionName, "--json"]

        switch action {
        case "open":
            guard let url = arguments.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                return "Error: 'url' is required for action 'open'"
            }
            guard let parsed = URL(string: url),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return "Error: URL must use http or https scheme"
            }
            let check = ToolSafety.shared.checkURL(parsed)
            guard check.allowed else {
                return "Error: URL blocked by security policy (\(check.reason ?? "blocked"))."
            }
            commandArgs += ["open", url]

        case "snapshot":
            commandArgs += ["snapshot", "-i"]

        case "click":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Browser click is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let selector = nonEmpty(arguments.selector) else {
                return "Error: 'selector' is required for action 'click'"
            }
            commandArgs += ["click", selector]

        case "fill":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Browser fill is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let selector = nonEmpty(arguments.selector) else {
                return "Error: 'selector' is required for action 'fill'"
            }
            guard let text = arguments.text else {
                return "Error: 'text' is required for action 'fill'"
            }
            commandArgs += ["fill", selector, text]

        case "type":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Browser type is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let selector = nonEmpty(arguments.selector) else {
                return "Error: 'selector' is required for action 'type'"
            }
            guard let text = arguments.text else {
                return "Error: 'text' is required for action 'type'"
            }
            commandArgs += ["type", selector, text]

        case "press":
            guard policy.allowDangerousWithoutConfirmation else {
                return "Error: Browser keypress is blocked by security profile '\(policy.profile.rawValue)'. Use --dangerous-without-confirm to allow."
            }
            guard let key = nonEmpty(arguments.key) else {
                return "Error: 'key' is required for action 'press'"
            }
            commandArgs += ["press", key]

        case "wait":
            if let selector = nonEmpty(arguments.selector) {
                commandArgs += ["wait", selector]
            } else {
                commandArgs += ["wait", "1500"]
            }

        case "get_text":
            guard let selector = nonEmpty(arguments.selector) else {
                return "Error: 'selector' is required for action 'get_text'"
            }
            commandArgs += ["get", "text", selector]

        case "get_url":
            commandArgs += ["get", "url"]

        case "get_title":
            commandArgs += ["get", "title"]

        case "screenshot":
            commandArgs += ["screenshot"]
            if let path = nonEmpty(arguments.path) {
                let check = ToolSafety.shared.checkPath(path, forWrite: true)
                guard check.allowed else {
                    return "Error: Screenshot path denied by security policy (\(check.reason ?? "blocked"))."
                }
                commandArgs.append(check.resolvedPath)
            }

        case "close":
            commandArgs += ["close"]

        default:
            return "Error: Unsupported action '\(action)'"
        }

        return runCommand(
            executablePath: executablePath,
            arguments: commandArgs,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runCommand(executablePath: String, arguments: [String], timeoutSeconds: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error launching agent-browser: \(error.localizedDescription)"
        }

        final class TimeoutState: @unchecked Sendable {
            var didTimeout = false
            let lock = NSLock()
            func markTimeout() {
                lock.lock()
                defer { lock.unlock() }
                didTimeout = true
            }
            func value() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return didTimeout
            }
        }

        let state = TimeoutState()
        let timer = DispatchWorkItem {
            state.markTimeout()
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds), execute: timer)

        process.waitUntilExit()
        timer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        var output = String(data: stdoutData, encoding: .utf8) ?? ""
        let errOutput = String(data: stderrData, encoding: .utf8) ?? ""

        if !errOutput.isEmpty {
            output += output.isEmpty ? "[stderr]\n\(errOutput)" : "\n[stderr]\n\(errOutput)"
        }

        if output.count > 100_000 {
            output = String(output.prefix(100_000)) + "\n... [truncated at 100KB]"
        }

        if state.value() {
            return "Error: agent-browser timed out after \(timeoutSeconds)s\n\(output)"
        }

        if process.terminationStatus != 0 {
            let details = output.isEmpty ? "(no output)" : output
            return "Error: agent-browser exited with code \(process.terminationStatus)\n\(details)"
        }

        return output.isEmpty ? "(no output)" : output
    }

    private func resolveExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = pathValue
            .split(separator: ":")
            .map { String($0) + "/" + name } +
            ["/usr/local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/bin/\(name)"]

        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func normalizedSessionName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "apple-code" : trimmed
    }
}
