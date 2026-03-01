import Foundation
import FoundationModels

struct WriteFileTool: Tool {
    let name = "writeFile"
    let description = "Write content to a file"

    @Generable
    struct Arguments {
        @Guide(description: "File path")
        let path: String
        @Guide(description: "File content")
        let content: String
    }

    func call(arguments: Arguments) async throws -> String {
        let url = URL(fileURLWithPath: arguments.path)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try arguments.content.write(to: url, atomically: true, encoding: .utf8)
            return "Successfully wrote \(arguments.content.count) characters to \(arguments.path)"
        } catch {
            return "Error writing file: \(error.localizedDescription)"
        }
    }
}
