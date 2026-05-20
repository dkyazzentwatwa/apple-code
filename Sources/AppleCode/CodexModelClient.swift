import Foundation
import FoundationModels

struct CodexProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol CodexProcessRunning: Sendable {
    func runCodex(
        arguments: [String],
        stdin: String,
        environment: [String: String]
    ) async throws -> CodexProcessResult
}

struct ShellCodexProcessRunner: CodexProcessRunning {
    func runCodex(
        arguments: [String],
        stdin: String,
        environment: [String: String]
    ) async throws -> CodexProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex"] + arguments
            process.environment = environment

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            if let data = stdin.data(using: .utf8) {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try stdinPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let stdout = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            return CodexProcessResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )
        }.value
    }
}

struct CodexModelClient: ModelClient {
    let config: ModelConfig
    let model: String?
    let runner: any CodexProcessRunning

    init(
        config: ModelConfig,
        model: String? = nil,
        runner: any CodexProcessRunning = ShellCodexProcessRunner()
    ) {
        self.config = config
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.runner = runner
    }

    func respond(
        prompt: String,
        tools: [any Tool],
        instructions: String
    ) async throws -> String {
        let outputURL = try makeOutputURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let workingDir = FileManager.default.currentDirectoryPath
        var arguments = [
            "exec",
            "--cd", workingDir,
            "--color", "never",
            "--sandbox", codexSandboxMode(),
            "--output-last-message", outputURL.path,
        ]
        if let model {
            arguments += ["--model", model]
        }
        arguments.append("-")

        let stdin = """
        \(instructions)

        ---
        User prompt:
        \(prompt)
        """

        let result = try await runner.runCodex(
            arguments: arguments,
            stdin: stdin,
            environment: codexEnvironment()
        )

        let finalMessage = readFinalMessage(from: outputURL)
        if result.exitCode != 0 {
            throw CodexModelClientError.processFailed(
                code: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout,
                finalMessage: finalMessage
            )
        }

        let reply = finalMessage ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw CodexModelClientError.emptyResponse(result.stderr)
        }
        return reply
    }

    func statusLines() -> [String] {
        var lines = [
            "Provider: codex",
            "Model: \(model ?? "Codex default")",
            "Sandbox: \(codexSandboxMode())",
        ]
        if let version = Self.codexVersion() {
            lines.append("Codex CLI: \(version)")
        } else {
            lines.append("Codex CLI: not found on PATH")
        }
        lines.append("Tools: delegated to Codex CLI")
        return lines
    }

    private func makeOutputURL() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".apple-code")
            .appendingPathComponent("codex")
        try SecureLocalStore.ensurePrivateDirectory(dir)
        return dir.appendingPathComponent("last-message-\(UUID().uuidString).txt")
    }

    private func readFinalMessage(from url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func codexSandboxMode() -> String {
        switch ToolSafety.shared.currentPolicy().profile {
        case .secure:
            return "read-only"
        case .balanced, .compatibility:
            return "workspace-write"
        }
    }

    private func codexEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        guard let codexPath = Self.whichCodex() else {
            return env
        }

        let codexDir = URL(fileURLWithPath: codexPath).deletingLastPathComponent().path
        let path = env["PATH"] ?? ""
        if !path.split(separator: ":").map(String.init).contains(codexDir) {
            env["PATH"] = path.isEmpty ? codexDir : "\(codexDir):\(path)"
        }
        return env
    }

    static func codexVersion() -> String? {
        runSimpleCodexCommand(arguments: ["--version"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func whichCodex() -> String? {
        runSimpleCommand(executable: "/usr/bin/which", arguments: ["codex"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func runSimpleCodexCommand(arguments: [String]) -> String? {
        runSimpleCommand(executable: "/usr/bin/env", arguments: ["codex"] + arguments)
    }

    private static func runSimpleCommand(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }
}

enum CodexModelClientError: LocalizedError {
    case processFailed(code: Int32, stderr: String, stdout: String, finalMessage: String?)
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let code, let stderr, let stdout, let finalMessage):
            let detail = [finalMessage, stderr, stdout]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .first ?? "no output"
            return "Codex CLI failed with exit code \(code): \(String(detail.prefix(1_200)))"
        case .emptyResponse(let stderr):
            let hint = stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "no response content"
            return "Codex CLI returned an empty response: \(hint)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
