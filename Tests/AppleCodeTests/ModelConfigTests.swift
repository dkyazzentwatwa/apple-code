import XCTest
@testable import apple_code

final class ModelConfigTests: XCTestCase {
    func testResolveDefaultsToAppleWithoutFlags() throws {
        let config = try ModelConfig.resolve(
            providerFlag: nil,
            modelFlag: nil,
            baseURLFlag: nil,
            env: [:]
        )

        XCTAssertEqual(config.provider, .apple)
        XCTAssertNil(config.model)
        XCTAssertNil(config.baseURL)
    }

    func testResolveInfersOllamaWhenModelProvided() throws {
        let config = try ModelConfig.resolve(
            providerFlag: nil,
            modelFlag: "qwen3.5:4b",
            baseURLFlag: nil,
            env: [:]
        )

        XCTAssertEqual(config.provider, .ollama)
        XCTAssertEqual(config.model, "qwen3.5:4b")
        XCTAssertEqual(config.baseURL, ModelConfig.defaultOllamaBaseURL)
    }

    func testResolveReadsEnvironmentForOllama() throws {
        let config = try ModelConfig.resolve(
            providerFlag: "ollama",
            modelFlag: nil,
            baseURLFlag: nil,
            env: [
                "OLLAMA_MODEL": "qwen2.5-coder:7b",
                "OLLAMA_BASE_URL": "http://localhost:11435"
            ]
        )

        XCTAssertEqual(config.provider, .ollama)
        XCTAssertEqual(config.model, "qwen2.5-coder:7b")
        XCTAssertEqual(config.baseURL, "http://localhost:11435")
    }

    func testResolveRejectsRemoteFlagsForApple() {
        XCTAssertThrowsError(
            try ModelConfig.resolve(
                providerFlag: "apple",
                modelFlag: "qwen3.5:4b",
                baseURLFlag: nil,
                env: [:]
            )
        ) { error in
            guard case ModelConfigError.appleDoesNotUseRemoteModelFlags = error else {
                XCTFail("Expected appleDoesNotUseRemoteModelFlags, got: \(error)")
                return
            }
        }
    }

    func testNormalizeBaseURLPreservesNativeOllamaBasePath() throws {
        let url = try ModelConfig.normalizeBaseURL("http://127.0.0.1:11434")
        XCTAssertEqual(url.absoluteString, ModelConfig.defaultOllamaBaseURL)
    }

    func testNormalizeBaseURLRejectsInvalidScheme() {
        XCTAssertThrowsError(try ModelConfig.normalizeBaseURL("ftp://localhost:11434")) { error in
            guard case ModelConfigError.invalidBaseURL(let value) = error else {
                XCTFail("Expected invalidBaseURL, got: \(error)")
                return
            }
            XCTAssertEqual(value, "ftp://localhost:11434")
        }
    }

    func testInvalidProviderProducesSpecificError() {
        XCTAssertThrowsError(
            try ModelConfig.resolve(
                providerFlag: "bad-provider",
                modelFlag: nil,
                baseURLFlag: nil,
                env: [:]
            )
        ) { error in
            guard case ModelConfigError.invalidProvider(let value) = error else {
                XCTFail("Expected invalidProvider, got: \(error)")
                return
            }
            XCTAssertEqual(value, "bad-provider")
        }
    }

    func testErrorDescriptionsCoverSpecialCases() {
        XCTAssertTrue(
            ModelConfigError.invalidProvider("openai-compatible").localizedDescription.contains("removed")
        )
        XCTAssertTrue(
            ModelConfigError.missingModel.localizedDescription.contains("requires a model")
        )
    }
}
