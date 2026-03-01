import Foundation
import FoundationModels

struct ListDirectoryTool: Tool {
    let name = "listDirectory"
    let description = "List directory contents"

    @Generable
    struct Arguments {
        @Guide(description: "Directory path")
        let path: String?
        @Guide(description: "Recurse into subdirs")
        let recursive: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        let dirPath = arguments.path ?? "."
        let url = URL(fileURLWithPath: dirPath)
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return "Error: Directory not found: \(dirPath)"
        }

        let isRecursive = arguments.recursive ?? false

        do {
            var entries: [String] = []
            if isRecursive {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if entries.count >= 500 {
                            entries.append("... [truncated at 500 entries]")
                            break
                        }
                        let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                        var isDir: ObjCBool = false
                        fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                        entries.append(isDir.boolValue ? "\(relativePath)/" : relativePath)
                    }
                }
            } else {
                let contents = try fm.contentsOfDirectory(atPath: url.path)
                for item in contents.sorted() {
                    var isDir: ObjCBool = false
                    let itemPath = url.appendingPathComponent(item).path
                    fm.fileExists(atPath: itemPath, isDirectory: &isDir)
                    entries.append(isDir.boolValue ? "\(item)/" : item)
                }
            }

            if entries.isEmpty {
                return "Directory is empty: \(dirPath)"
            }
            return entries.joined(separator: "\n")
        } catch {
            return "Error listing directory: \(error.localizedDescription)"
        }
    }
}
