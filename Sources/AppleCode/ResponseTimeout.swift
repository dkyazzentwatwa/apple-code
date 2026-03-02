import Foundation

enum ResponseTimeoutError: LocalizedError {
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Response timed out after \(seconds)s"
        }
    }
}

func withResponseTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let clampedSeconds = max(1, seconds)
    let nanoseconds = UInt64(clampedSeconds) * 1_000_000_000

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw ResponseTimeoutError.timedOut(seconds: clampedSeconds)
        }

        guard let first = try await group.next() else {
            throw ResponseTimeoutError.timedOut(seconds: clampedSeconds)
        }
        group.cancelAll()
        return first
    }
}
