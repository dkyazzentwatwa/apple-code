import Foundation
import FoundationModels

struct EditFileTool: Tool {
    let name = "editFile"
    let description = "Edit a file by replacing an exact string with a new string. oldString must appear exactly once in the file."

    @Generable
    struct Arguments {
        @Guide(description: "File path")
        let path: String
        @Guide(description: "Exact string to find (must appear exactly once)")
        let oldString: String
        @Guide(description: "Replacement string")
        let newString: String
    }

    func call(arguments: Arguments) async throws -> String {
        let check = ToolSafety.shared.checkPath(arguments.path, forWrite: true)
        guard check.allowed else {
            return "Error: Access denied for path '\(arguments.path)' (\(check.reason ?? "blocked"))."
        }

        let url = URL(fileURLWithPath: check.resolvedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Error: File not found: \(arguments.path)"
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }

        let occurrences = content.ranges(of: arguments.oldString).count
        if occurrences == 0 {
            return "Error: oldString not found in \(check.resolvedPath)"
        }
        if occurrences > 1 {
            return "Error: oldString appears \(occurrences) times in \(check.resolvedPath). Provide a more specific string that matches exactly once."
        }

        let newContent = content.replacingOccurrences(of: arguments.oldString, with: arguments.newString)

        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return "Error writing file: \(error.localizedDescription)"
        }

        // Find the line number of the replacement
        let lineNumber = lineNumberOf(string: arguments.oldString, in: content)
        let oldLines = arguments.oldString.components(separatedBy: "\n").count
        let newLines = arguments.newString.components(separatedBy: "\n").count
        let lineDelta = newLines - oldLines
        let deltaStr = lineDelta == 0 ? "" : (lineDelta > 0 ? " (+\(lineDelta) lines)" : " (\(lineDelta) lines)")
        return "Replaced 1 occurrence at line \(lineNumber) in \(check.resolvedPath)\(deltaStr)"
    }

    private func lineNumberOf(string: String, in content: String) -> Int {
        guard let range = content.range(of: string) else { return 1 }
        let before = content[content.startIndex..<range.lowerBound]
        return before.components(separatedBy: "\n").count
    }
}

private extension String {
    func ranges(of substring: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = self.startIndex
        while start < self.endIndex,
              let range = self.range(of: substring, range: start..<self.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}
