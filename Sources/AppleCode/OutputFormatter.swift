import Foundation

enum OutputFormatter {
    static func format(_ message: String, verbose: Bool) -> String {
        if verbose { return message }
        if !looksToolHeavy(message) { return message }

        // Default view is summary-first for dense tool output; full body is opt-in via --verbose.
        let lines = message.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let previewCount = min(10, nonEmpty.count)
        let preview = nonEmpty.prefix(previewCount).joined(separator: "\n")
        let omitted = max(0, nonEmpty.count - previewCount)

        var summary = "[summary] \(nonEmpty.count) lines"
        if omitted > 0 {
            summary += ", showing first \(previewCount). Re-run with --verbose for full output."
        }

        if preview.isEmpty { return summary }
        return "\(summary)\n\n\(preview)"
    }

    private static func looksToolHeavy(_ message: String) -> Bool {
        if message.count > 2400 { return true }
        let lines = message.components(separatedBy: .newlines)
        if lines.count > 40 { return true }

        let lower = message.lowercased()
        if lower.contains("[truncated") || lower.contains("status:") { return true }
        if lower.contains("apple notes:") || lower.contains("apple reminders:") || lower.contains("apple calendar:") { return true }
        if message.range(of: #"(?m)^\s*\d+\.\s"#, options: .regularExpression) != nil {
            return lines.count >= 12
        }
        return false
    }
}
