import Foundation
import FoundationModels

struct SearchFilesTool: Tool {
    let name = "searchFiles"
    let description = "Find files by glob pattern"

    @Generable
    struct Arguments {
        @Guide(description: "Glob like *.swift")
        let pattern: String
        @Guide(description: "Search directory")
        let path: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let searchPath = arguments.path ?? "."
        let url = URL(fileURLWithPath: searchPath)
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return "Error: Directory not found: \(searchPath)"
        }

        var matches: [String] = []
        let pattern = arguments.pattern

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return "Error: Cannot enumerate directory: \(searchPath)"
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if matches.count >= 200 {
                matches.append("... [truncated at 200 results]")
                break
            }
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let fileName = fileURL.lastPathComponent

            // Match against filename or relative path
            if fnmatch(pattern, fileName, FNM_PATHNAME) == 0 ||
               fnmatch(pattern, relativePath, FNM_PATHNAME) == 0 {
                matches.append(relativePath)
            }
        }

        if matches.isEmpty {
            return "No files found matching '\(pattern)' in \(searchPath)"
        }
        return matches.joined(separator: "\n")
    }
}
