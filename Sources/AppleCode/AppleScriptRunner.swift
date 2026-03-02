import Foundation

enum AppleScriptRunner {
    struct ExecutionResult {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
        let timedOut: Bool

        var succeeded: Bool {
            !timedOut && terminationStatus == 0
        }
    }

    /// Run AppleScript and return full execution details.
    static func runDetailed(_ script: String, timeout: TimeInterval = 30) -> ExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class TimeoutState: @unchecked Sendable {
            var didTimeout = false
            let lock = NSLock()
            func markTimedOut() {
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

        do {
            try process.run()
        } catch {
            return ExecutionResult(
                stdout: "",
                stderr: "Failed to run osascript: \(error.localizedDescription)",
                terminationStatus: -1,
                timedOut: false
            )
        }

        let state = TimeoutState()
        let timer = DispatchWorkItem {
            state.markTimedOut()
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        process.waitUntilExit()
        timer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        return ExecutionResult(
            stdout: stdout,
            stderr: stderr,
            terminationStatus: process.terminationStatus,
            timedOut: state.value()
        )
    }

    /// Run an AppleScript via osascript -e. Returns stdout or nil on failure.
    static func run(_ script: String, timeout: TimeInterval = 30) -> String? {
        let result = runDetailed(script, timeout: timeout)
        guard result.succeeded else { return nil }
        return result.stdout
    }

    static func classifyFailure(_ result: ExecutionResult, appName: String) -> String {
        if result.timedOut {
            return "\(appName) timed out. Ensure the app is responsive and permission prompts are accepted."
        }

        let lower = result.stderr.lowercased()
        if lower.contains("not authorized")
            || lower.contains("not permitted")
            || lower.contains("operation not permitted")
            || lower.contains("(-1743)") {
            return "Permission denied. Allow apple-code (or Terminal/iTerm) in System Settings > Privacy & Security > Automation."
        }
        if lower.contains("application isn") && lower.contains("running") {
            return "\(appName) is not running or unavailable."
        }
        if lower.contains("can") && lower.contains("get") {
            return "Requested data could not be read from \(appName)."
        }
        if !result.stderr.isEmpty {
            return result.stderr
        }
        return "\(appName) returned exit code \(result.terminationStatus)."
    }

    /// Parse tab-delimited AppleScript output into an array of dictionaries.
    static func parseDelimited(_ raw: String?, fieldNames: [String]) -> [[String: String]] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let expected = fieldNames.count
        var records: [[String: String]] = []
        for line in raw.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            if parts.count != expected { continue }
            var record: [String: String] = [:]
            for (i, name) in fieldNames.enumerated() {
                record[name] = parts[i]
            }
            records.append(record)
        }
        return records
    }

    /// Escape a string for safe embedding in AppleScript string literals.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Format records as a simple text summary.
    static func formatRecords(_ records: [[String: String]], formatter: (([String: String]) -> String)? = nil) -> String {
        if records.isEmpty { return "No results found." }
        if let fmt = formatter {
            return records.map(fmt).joined(separator: "\n")
        }
        return records.map { $0.values.joined(separator: " | ") }.joined(separator: "\n")
    }
}
