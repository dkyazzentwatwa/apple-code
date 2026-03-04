import Foundation
import FoundationModels

struct GitTool: Tool {
    let name = "git"
    let description = "Perform git operations: status, diff, log, commit, stash, branch_list, blame"

    @Generable
    struct Arguments {
        @Guide(description: "Action: status | diff | log | commit | stash | branch_list | blame")
        let action: String
        @Guide(description: "File path for blame, or commit message for commit, or stash operation (push/pop/list) for stash")
        let arg: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action.trimmingCharacters(in: .whitespaces).lowercased() {
        case "status":
            return await runGit(["status", "--short", "--branch"])

        case "diff":
            let path = arguments.arg?.trimmingCharacters(in: .whitespacesAndNewlines)
            var gitArgs = ["diff", "--stat", "-p", "--no-color"]
            if let path, !path.isEmpty { gitArgs.append(path) }
            return capOutput(await runGit(gitArgs), maxChars: 8000)

        case "log":
            return await runGit([
                "log", "--oneline", "--decorate", "--graph",
                "--max-count=20", "--no-color",
            ])

        case "commit":
            guard let message = arguments.arg?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                return "Error: commit requires a message in arg"
            }
            let staged = await runGit(["diff", "--cached", "--name-only"])
            if staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Error: No staged changes. Run 'git add' first."
            }
            return await runGit(["commit", "-m", message])

        case "stash":
            let op = arguments.arg?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "list"
            switch op {
            case "push":   return await runGit(["stash", "push"])
            case "pop":    return await runGit(["stash", "pop"])
            default:       return await runGit(["stash", "list"])
            }

        case "branch_list", "branches":
            return await runGit(["branch", "-a", "--no-color"])

        case "blame":
            guard let path = arguments.arg?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return "Error: blame requires a file path in arg"
            }
            return capOutput(await runGit(["blame", "--no-progress", path]), maxChars: 6000)

        default:
            return "Error: Unknown git action '\(arguments.action)'. Use status|diff|log|commit|stash|branch_list|blame"
        }
    }

    private func runGit(_ args: [String]) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error launching git: \(error.localizedDescription)"
        }

        process.waitUntilExit()

        let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var result = out
        if !err.isEmpty {
            result += err
        }
        return result.trimmingCharacters(in: .newlines).isEmpty ? "(no output)" : result
    }

    func capOutput(_ output: String, maxChars: Int) -> String {
        guard output.count > maxChars else { return output }
        return String(output.prefix(maxChars)) + "\n... [truncated at \(maxChars) chars]"
    }
}
