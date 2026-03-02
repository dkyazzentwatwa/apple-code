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
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        let line = "[\(ts)] \(message)\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    return
                }
            }
        } else {
            try? data.write(to: url)
        }
    }
}
