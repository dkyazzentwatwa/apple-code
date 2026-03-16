import Foundation
import FoundationModels

struct WriteFileTool: Tool {
    let name = "writeFile"
    let description = "Write content to a file. For targeted edits to existing files, prefer editFile."

    @Generable
    struct Arguments {
        @Guide(description: "File path")
        let path: String
        @Guide(description: "File content")
        let content: String
    }

    func call(arguments: Arguments) async throws -> String {
        let check = ToolSafety.shared.checkPath(arguments.path, forWrite: true)
        guard check.allowed else {
            return "Error: Access denied for path '\(arguments.path)' (\(check.reason ?? "blocked"))."
        }

        let url = URL(fileURLWithPath: check.resolvedPath)
        let dir = url.deletingLastPathComponent()
        let alreadyExists = FileManager.default.fileExists(atPath: url.path)
        if alreadyExists {
            appendAuditLog(path: check.resolvedPath, action: "OVERWRITE")
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try arguments.content.write(to: url, atomically: true, encoding: .utf8)
            let notice = alreadyExists ? " (overwrote existing file)" : ""
            return "Successfully wrote \(arguments.content.count) characters to \(check.resolvedPath)\(notice)"
        } catch {
            return "Error writing file: \(error.localizedDescription)"
        }
    }

    private func appendAuditLog(path: String, action: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".apple-code")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logURL = dir.appendingPathComponent("command_audit.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(action): \(path)\n"
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
