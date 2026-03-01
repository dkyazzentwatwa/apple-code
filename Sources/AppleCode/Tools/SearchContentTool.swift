import Foundation
import FoundationModels

struct SearchContentTool: Tool {
    let name = "searchContent"
    let description = "Grep file contents for text"

    @Generable
    struct Arguments {
        @Guide(description: "Search text")
        let pattern: String
        @Guide(description: "Search directory")
        let path: String?
        @Guide(description: "File filter like *.swift")
        let filePattern: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let searchPath = arguments.path ?? "."
        let url = URL(fileURLWithPath: searchPath)
        let fm = FileManager.default
        let query = arguments.pattern.lowercased()
        let fileFilter = arguments.filePattern

        guard fm.fileExists(atPath: url.path) else {
            return "Error: Directory not found: \(searchPath)"
        }

        var results: [String] = []

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return "Error: Cannot enumerate directory: \(searchPath)"
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if results.count >= 100 { break }

            // Skip directories
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            // Apply file pattern filter
            if let filter = fileFilter {
                if fnmatch(filter, fileURL.lastPathComponent, 0) != 0 { continue }
            }

            // Read and search
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let lines = content.components(separatedBy: "\n")

            for (lineNum, line) in lines.enumerated() {
                if results.count >= 100 {
                    results.append("... [truncated at 100 matches]")
                    break
                }
                if line.lowercased().contains(query) {
                    let trimmed = line.count > 200 ? String(line.prefix(200)) + "..." : line
                    results.append("\(relativePath):\(lineNum + 1): \(trimmed)")
                }
            }
        }

        if results.isEmpty {
            return "No matches found for '\(arguments.pattern)' in \(searchPath)"
        }
        return results.joined(separator: "\n")
    }
}
