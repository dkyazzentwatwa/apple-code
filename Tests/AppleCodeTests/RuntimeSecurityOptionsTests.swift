import XCTest
import Foundation
@testable import apple_code

final class RuntimeSecurityOptionsTests: XCTestCase {
    private var previousPolicy: ToolSafetyPolicy?
    private var previousRedaction: PrivacyRedactionMode?

    override func setUp() {
        super.setUp()
        previousPolicy = ToolSafety.shared.currentPolicy()
        previousRedaction = PrivacyRedactor.shared.currentMode()
    }

    override func tearDown() {
        if let previousPolicy {
            ToolSafety.shared.configure(previousPolicy)
        }
        if let previousRedaction {
            PrivacyRedactor.shared.configure(mode: previousRedaction)
        }
        super.tearDown()
    }

    func testResolveDefaultsToSecureAndLogRedaction() throws {
        let options = try RuntimeSecurityOptions.resolve(
            config: .empty,
            cli: RuntimeSecurityCLIOverrides()
        )

        XCTAssertEqual(options.profile, .secure)
        XCTAssertEqual(options.privacyRedactionMode, .logs)
        XCTAssertNil(options.allowPrivateNetwork)
        XCTAssertNil(options.allowDangerousWithoutConfirmation)
        XCTAssertNil(options.allowAutomaticFallbackExecution)
    }

    func testCLIOverridesConfigAndMergesLists() throws {
        var config = AppConfig.empty
        config.securityProfile = "balanced"
        config.allowPaths = ["/tmp/config"]
        config.allowHosts = ["example.com"]
        config.allowPrivateNetwork = false
        config.dangerousWithoutConfirm = false
        config.allowFallbackExecution = false
        config.privacyRedaction = "off"

        var cli = RuntimeSecurityCLIOverrides()
        cli.securityProfile = "compatibility"
        cli.allowPaths = ["/tmp/cli"]
        cli.allowHosts = ["developer.apple.com"]
        cli.allowPrivateNetwork = true
        cli.dangerousWithoutConfirm = true
        cli.allowFallbackExecution = true
        cli.privacyRedaction = "all"

        let options = try RuntimeSecurityOptions.resolve(config: config, cli: cli)

        XCTAssertEqual(options.profile, .compatibility)
        XCTAssertEqual(options.additionalAllowedRoots, ["/tmp/cli", "/tmp/config"])
        XCTAssertEqual(options.allowedHosts, ["developer.apple.com", "example.com"])
        XCTAssertEqual(options.allowPrivateNetwork, true)
        XCTAssertEqual(options.allowDangerousWithoutConfirmation, true)
        XCTAssertEqual(options.allowAutomaticFallbackExecution, true)
        XCTAssertEqual(options.privacyRedactionMode, .all)
    }

    func testConfigureRuntimeAppliesPolicyAndPrivacy() throws {
        var cli = RuntimeSecurityCLIOverrides()
        cli.securityProfile = "secure"
        cli.allowPaths = [FileManager.default.temporaryDirectory.path]
        cli.allowHosts = ["developer.apple.com"]
        cli.privacyRedaction = "transcripts"

        let options = try RuntimeSecurityOptions.resolve(config: .empty, cli: cli)
        options.configureRuntime(workingDirectory: FileManager.default.currentDirectoryPath)

        let policy = ToolSafety.shared.currentPolicy()
        XCTAssertEqual(policy.profile, .secure)
        XCTAssertTrue(policy.allowedRoots.contains(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue(policy.allowedHosts.contains("developer.apple.com"))
        XCTAssertEqual(PrivacyRedactor.shared.currentMode(), .transcripts)
    }

    func testRejectsInvalidSecurityAndRedactionModes() {
        var badProfile = RuntimeSecurityCLIOverrides()
        badProfile.securityProfile = "wild"
        XCTAssertThrowsError(try RuntimeSecurityOptions.resolve(config: .empty, cli: badProfile)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid security profile"))
        }

        var badRedaction = RuntimeSecurityCLIOverrides()
        badRedaction.privacyRedaction = "maybe"
        XCTAssertThrowsError(try RuntimeSecurityOptions.resolve(config: .empty, cli: badRedaction)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid privacy redaction"))
        }
    }

    func testPrivacyRedactionModesAndPatterns() {
        XCTAssertEqual(PrivacyRedactionMode.parse("off"), .off)
        XCTAssertEqual(PrivacyRedactionMode.parse("logs"), .logs)
        XCTAssertEqual(PrivacyRedactionMode.parse("transcripts"), .transcripts)
        XCTAssertEqual(PrivacyRedactionMode.parse("all"), .all)
        XCTAssertNil(PrivacyRedactionMode.parse("unknown"))

        XCTAssertFalse(PrivacyRedactionMode.off.redactLogs)
        XCTAssertTrue(PrivacyRedactionMode.logs.redactLogs)
        XCTAssertFalse(PrivacyRedactionMode.logs.redactTranscripts)
        XCTAssertTrue(PrivacyRedactionMode.transcripts.redactTranscripts)
        XCTAssertTrue(PrivacyRedactionMode.all.redactLogs)
        XCTAssertTrue(PrivacyRedactionMode.all.redactTranscripts)

        let redacted = PrivacyRedactor.redact(
            "api_key=abc12345 token: secretvalue Bearer abcdefghijklmnop me@example.com 555-123-4567"
        )
        XCTAssertTrue(redacted.contains("api_key=[REDACTED]"))
        XCTAssertTrue(redacted.contains("token=[REDACTED]"))
        XCTAssertTrue(redacted.contains("Bearer [REDACTED]"))
        XCTAssertTrue(redacted.contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(redacted.contains("[REDACTED_PHONE]"))
    }
}
