import Foundation

final class UILogger: @unchecked Sendable {
    static let shared = UILogger()

    private let lock = NSLock()
    private var logFileURL: URL?

    private init() {}

    func configure(directory: URL) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try SecureLocalStore.ensurePrivateDirectory(directory)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = "apple-code-\(formatter.string(from: Date())).log"
            logFileURL = directory.appendingPathComponent(fileName)
        } catch {
            logFileURL = nil
        }
    }

    func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logFileURL else { return }

        let ts = ISO8601DateFormatter().string(from: Date())
        let safeMessage = PrivacyRedactor.shared.redactForLogs(message)
        SecureLocalStore.appendPrivateLine("[\(ts)] \(safeMessage)\n", to: url)
    }
}
