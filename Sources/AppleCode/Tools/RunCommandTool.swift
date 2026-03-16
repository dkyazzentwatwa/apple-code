import Foundation
import FoundationModels

struct RunCommandTool: Tool {
    let name = "runCommand"
    let description = "Run a shell command"

    @Generable
    struct Arguments {
        @Guide(description: "Shell command")
        let command: String
        @Guide(description: "Timeout seconds")
        let timeout: Int?
    }

    // Patterns that are always blocked (catastrophic, no confirmation)
    private static let hardBlockPatterns: [NSRegularExpression] = [
        "rm\\s+-[a-z]*r[a-z]*f\\s+/[^/]",  // rm -rf /<something> (root paths)
        "rm\\s+-[a-z]*r[a-z]*f\\s+/\\s*$",  // rm -rf / (trailing space/end)
        "mkfs\\b",
        "dd\\s+if=",
        ":\\(\\)\\s*\\{",                    // fork bomb :() {
        ">\\s*/dev/sd",
        "chmod\\s+-R\\s+777\\s+/",
        "\\bshutdown\\b",
        "\\breboot\\b",
        "\\bhalt\\b",
        "\\bpoweroff\\b",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    // Patterns that need user confirmation before running
    private static let warnPatterns: [NSRegularExpression] = [
        "\\brm\\b.*-[a-z]*r",               // any recursive rm
        "\\bsudo\\b",                        // sudo anything
        "\\bcurl\\b.*\\|.*\\bsh\\b",         // curl | sh
        "\\bwget\\b.*\\|.*\\bsh\\b",         // wget | sh
        "\\bchmod\\b.*777",
        "\\bmv\\b.*\\/dev\\/null",
        "> /etc/",                            // overwrite system files
        "\\bkillall\\b",
        "\\bkill\\s+-9\\b",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    enum CommandRisk {
        case safe
        case warn(reason: String)
        case blocked(reason: String)
    }

    static func assess(_ command: String) -> CommandRisk {
        let range = NSRange(command.startIndex..., in: command)
        for pattern in hardBlockPatterns {
            if pattern.firstMatch(in: command, range: range) != nil {
                return .blocked(reason: "dangerous destructive command")
            }
        }
        for pattern in warnPatterns {
            if pattern.firstMatch(in: command, range: range) != nil {
                return .warn(reason: "potentially dangerous command")
            }
        }
        return .safe
    }

    func call(arguments: Arguments) async throws -> String {
        let cmd = arguments.command
        let policy = ToolSafety.shared.currentPolicy()

        switch Self.assess(cmd) {
        case .blocked(let reason):
            appendAuditLog(command: cmd, decision: "BLOCKED", reason: reason)
            return "Error: Command blocked for safety: \(reason). Command: \(cmd)"
        case .warn(let reason):
            if !policy.allowDangerousWithoutConfirmation {
                appendAuditLog(command: cmd, decision: "BLOCKED-WARN", reason: reason)
                return """
                Error: Command requires explicit confirmation under the active security policy (\(policy.profile.rawValue)).
                Blocked command: \(cmd)
                Reason: \(reason)
                Hint: rerun apple-code with --dangerous-without-confirm only if you trust this command.
                """
            }
            appendAuditLog(command: cmd, decision: "ALLOWED-WARN", reason: reason)
        case .safe:
            break
        }

        let timeoutSecs = arguments.timeout ?? 30

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error launching command: \(error.localizedDescription)"
        }

        final class TimeoutState: @unchecked Sendable {
            var didTimeout = false
            let lock = NSLock()
            func markTimeout() {
                lock.lock(); defer { lock.unlock() }
                didTimeout = true
            }
            func value() -> Bool {
                lock.lock(); defer { lock.unlock() }
                return didTimeout
            }
        }

        let state = TimeoutState()
        let timer = DispatchWorkItem {
            state.markTimeout()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSecs), execute: timer)
        process.waitUntilExit()
        timer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        var output = String(data: stdoutData, encoding: .utf8) ?? ""
        let errOutput = String(data: stderrData, encoding: .utf8) ?? ""

        if !errOutput.isEmpty {
            output += "\n[stderr]\n\(errOutput)"
        }

        if process.terminationStatus != 0 && !state.value() {
            output += "\n[exit code: \(process.terminationStatus)]"
        }

        if state.value() {
            output += "\n[timed out after \(timeoutSecs)s]"
        }

        if output.count > 100_000 {
            output = String(output.prefix(100_000)) + "\n... [truncated at 100KB]"
        }

        return output.isEmpty ? "(no output)" : output
    }

    private func appendAuditLog(command: String, decision: String, reason: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".apple-code")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logURL = dir.appendingPathComponent("command_audit.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(decision) (\(reason)): \(command)\n"
        if let data = entry.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: logURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
