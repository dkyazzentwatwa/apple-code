import Foundation

struct TUIConfig {
    let verbose: Bool
    let spinnerDelayMs: UInt64
    let longOpThresholdSeconds: TimeInterval
    let logsDirectory: URL

    static func `default`(verbose: Bool) -> TUIConfig {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".apple-code/logs", isDirectory: true)
        return TUIConfig(
            verbose: verbose,
            spinnerDelayMs: 200,
            longOpThresholdSeconds: 1.0,
            logsDirectory: logsDir
        )
    }
}
