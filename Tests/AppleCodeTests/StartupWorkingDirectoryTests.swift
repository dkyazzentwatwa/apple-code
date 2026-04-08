import XCTest
import Foundation
@testable import apple_code

final class StartupWorkingDirectoryTests: XCTestCase {
    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-code-startup-cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPrepareStartupWorkingDirectoryChangesIntoValidDirectory() throws {
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDirectory) }

        let directory = try tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolvedDirectory = try prepareStartupWorkingDirectory(cwd: directory.path)

        XCTAssertEqual(normalizedPath(resolvedDirectory), normalizedPath(directory.path))
        XCTAssertEqual(normalizedPath(FileManager.default.currentDirectoryPath), normalizedPath(directory.path))
    }

    func testPrepareStartupWorkingDirectoryFailsForMissingPath() throws {
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDirectory) }

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-code-missing-\(UUID().uuidString)", isDirectory: true)
            .path

        XCTAssertThrowsError(try prepareStartupWorkingDirectory(cwd: missingPath)) { error in
            XCTAssertEqual(error.localizedDescription, "Working directory not found: \(missingPath)")
        }
        XCTAssertEqual(FileManager.default.currentDirectoryPath, originalDirectory)
    }

    func testPrepareStartupWorkingDirectoryFailsForFilePath() throws {
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDirectory) }

        let directory = try tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("not-a-directory.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try prepareStartupWorkingDirectory(cwd: file.path)) { error in
            XCTAssertEqual(error.localizedDescription, "Working directory is not a directory: \(file.path)")
        }
        XCTAssertEqual(FileManager.default.currentDirectoryPath, originalDirectory)
    }
}
