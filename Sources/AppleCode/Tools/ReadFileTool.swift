import Foundation
import FoundationModels

struct ReadFileTool: Tool {
    let name = "readFile"
    let description = "Read a file's contents"

    @Generable
    struct Arguments {
        @Guide(description: "File path")
        let path: String
    }

    func call(arguments: Arguments) async throws -> String {
        let url = URL(fileURLWithPath: arguments.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Error: File not found: \(arguments.path)"
        }
        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            if content.count > 50000 {
                content = String(content.prefix(50000)) + "\n... [truncated at 50KB]"
            }
            return content
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }
    }
}
