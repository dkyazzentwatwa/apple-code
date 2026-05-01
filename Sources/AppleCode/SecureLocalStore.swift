import Foundation
import Darwin

enum SecureLocalStore {
    static func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        chmod(url.path, S_IRWXU)
    }

    static func writePrivateFile(data: Data, to url: URL) throws {
        try ensurePrivateDirectory(url.deletingLastPathComponent())
        try data.write(to: url)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }

    static func appendPrivateLine(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }

        do {
            try ensurePrivateDirectory(url.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url)
            }
            chmod(url.path, S_IRUSR | S_IWUSR)
        } catch {
            return
        }
    }

    static func mode(for url: URL) -> mode_t? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return info.st_mode & mode_t(0o777)
    }
}
