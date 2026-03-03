import XCTest
@testable import apple_code

final class ResponseTimeoutTests: XCTestCase {
    func testOperationCompletesBeforeTimeout() async throws {
        let value: Int = try await withResponseTimeout(seconds: 1) {
            42
        }
        XCTAssertEqual(value, 42)
    }

    func testOperationTimesOut() async {
        do {
            _ = try await withResponseTimeout(seconds: 1) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout")
        } catch let error as ResponseTimeoutError {
            switch error {
            case .timedOut(let seconds):
                XCTAssertEqual(seconds, 1)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
