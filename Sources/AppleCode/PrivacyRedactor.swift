import Foundation

enum PrivacyRedactionMode: String, Codable, Sendable {
    case off
    case logs
    case transcripts
    case all

    static func parse(_ raw: String?) -> PrivacyRedactionMode? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off", "none", "false", "0":
            return .off
        case "logs", "log":
            return .logs
        case "transcripts", "transcript", "sessions", "session":
            return .transcripts
        case "all", "true", "1", "on":
            return .all
        default:
            return nil
        }
    }

    var redactLogs: Bool {
        self == .logs || self == .all
    }

    var redactTranscripts: Bool {
        self == .transcripts || self == .all
    }
}

final class PrivacyRedactor: @unchecked Sendable {
    static let shared = PrivacyRedactor()

    private let lock = NSLock()
    private var mode: PrivacyRedactionMode = .logs

    private init() {}

    func configure(mode: PrivacyRedactionMode) {
        lock.lock()
        self.mode = mode
        lock.unlock()
    }

    func currentMode() -> PrivacyRedactionMode {
        lock.lock()
        let snapshot = mode
        lock.unlock()
        return snapshot
    }

    func redactForLogs(_ text: String) -> String {
        currentMode().redactLogs ? Self.redact(text) : text
    }

    func redactForTranscripts(_ text: String) -> String {
        currentMode().redactTranscripts ? Self.redact(text) : text
    }

    static func redact(_ text: String) -> String {
        var redacted = text
        let replacements: [(String, String)] = [
            (##"(?i)\b(api[_-]?key|token|secret|password|passwd|authorization)\s*[:=]\s*["']?[^"'\s,;]+"?"##, "$1=[REDACTED]"),
            (#"(?i)\b(Bearer)\s+[A-Za-z0-9._~+/=-]{12,}"#, "$1 [REDACTED]"),
            (#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#, "[REDACTED_EMAIL]"),
            (#"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, "[REDACTED_PHONE]"),
        ]
        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression]
            )
        }
        return redacted
    }
}
