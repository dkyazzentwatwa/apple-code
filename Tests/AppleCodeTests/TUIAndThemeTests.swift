import XCTest
@testable import apple_code

final class TUIAndThemeTests: XCTestCase {
    func testThemeLookupAndCatalog() {
        XCTAssertEqual(TUITheme.all.count, 6)
        XCTAssertEqual(TUITheme.named("  OCEAN ")?.name, "ocean")
        XCTAssertNil(TUITheme.named(nil))
        XCTAssertNil(TUITheme.named(""))
        XCTAssertNil(TUITheme.named("missing"))
    }

    func testTUIConfigDefaults() {
        let config = TUIConfig.default(verbose: true)
        XCTAssertTrue(config.verbose)
        XCTAssertEqual(config.spinnerDelayMs, 200)
        XCTAssertEqual(config.longOpThresholdSeconds, 1.0)
        XCTAssertTrue(config.logsDirectory.path.contains(".apple-code/logs"))
    }

    func testTerminalCapabilitiesDetectDoesNotCrash() {
        let caps = TerminalCapabilities.detect()
        _ = caps.supportsAdvancedUI
        _ = caps.supportsUnicode
        _ = caps.supportsTrueColor
        _ = caps.supportsModifiedEnter
        XCTAssertTrue(true)
    }
}
