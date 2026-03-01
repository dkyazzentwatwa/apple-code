import Foundation

enum AppleScriptRunner {
    /// Run an AppleScript via osascript -e. Returns stdout or nil on failure.
    static func run(_ script: String, timeout: TimeInterval = 30) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let timer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        process.waitUntilExit()
        timer.cancel()

        guard process.terminationStatus == 0 else { return nil }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse tab-delimited AppleScript output into an array of dictionaries.
    static func parseDelimited(_ raw: String?, fieldNames: [String]) -> [[String: String]] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let expected = fieldNames.count
        var records: [[String: String]] = []
        for line in raw.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            if parts.count != expected { continue }
            var record: [String: String] = [:]
            for (i, name) in fieldNames.enumerated() {
                record[name] = parts[i]
            }
            records.append(record)
        }
        return records
    }

    /// Escape a string for safe embedding in AppleScript string literals.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Format records as a simple text summary.
    static func formatRecords(_ records: [[String: String]], formatter: (([String: String]) -> String)? = nil) -> String {
        if records.isEmpty { return "No results found." }
        if let fmt = formatter {
            return records.map(fmt).joined(separator: "\n")
        }
        return records.map { $0.values.joined(separator: " | ") }.joined(separator: "\n")
    }
}
