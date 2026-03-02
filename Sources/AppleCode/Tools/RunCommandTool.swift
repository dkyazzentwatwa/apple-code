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

    private static let blocklist = [
        "rm -rf /", "rm -rf /*", "mkfs", "dd if=", ":(){", "fork bomb",
        "> /dev/sda", "chmod -R 777 /", "shutdown", "reboot", "halt",
    ]

    func call(arguments: Arguments) async throws -> String {
        let cmd = arguments.command

        // Safety check
        for blocked in Self.blocklist {
            if cmd.contains(blocked) {
                return "Error: Command blocked for safety: contains '\(blocked)'"
            }
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

        let didTimeout = state.value()

        if process.terminationStatus != 0 && !didTimeout {
            output += "\n[exit code: \(process.terminationStatus)]"
        }

        if didTimeout {
            output += "\n[timed out after \(timeoutSecs)s]"
        }

        // Cap output at 100KB
        if output.count > 100_000 {
            output = String(output.prefix(100_000)) + "\n... [truncated at 100KB]"
        }

        return output.isEmpty ? "(no output)" : output
    }
}
