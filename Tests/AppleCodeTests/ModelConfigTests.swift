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

    func testResolveCodexProviderWithModelFlag() throws {
        let config = try ModelConfig.resolve(
            providerFlag: "codex-cli",
            modelFlag: "gpt-5.2",
            baseURLFlag: nil,
            env: [:]
        )

        XCTAssertEqual(config.provider, .codex)
        XCTAssertEqual(config.model, "gpt-5.2")
        XCTAssertNil(config.baseURL)
    }

    func testResolveCodexReadsEnvironmentModel() throws {
        let config = try ModelConfig.resolve(
            providerFlag: "codex",
            modelFlag: nil,
            baseURLFlag: nil,
            env: ["CODEX_MODEL": "gpt-5.4-mini"]
        )

        XCTAssertEqual(config.provider, .codex)
        XCTAssertEqual(config.model, "gpt-5.4-mini")
        XCTAssertNil(config.baseURL)
    }

    func testResolveCodexUsesDefaultModel() throws {
        let config = try ModelConfig.resolve(
            providerFlag: "codex",
            modelFlag: nil,
            baseURLFlag: nil,
            env: [:]
        )

        XCTAssertEqual(config.provider, .codex)
        XCTAssertEqual(config.model, "gpt-5.4")
        XCTAssertNil(config.baseURL)
    }

    func testResolveApplePCCAliasesAndReasoning() throws {
        let config = try ModelConfig.resolve(
            providerFlag: "private-cloud-compute",
            modelFlag: nil,
            baseURLFlag: nil,
            reasoningFlag: "deep",
            env: [:]
        )

        XCTAssertEqual(config.provider, .applePCC)
        XCTAssertEqual(config.reasoningLevel, .deep)
        XCTAssertNil(config.model)
        XCTAssertNil(config.baseURL)
    }

    func testResolveRejectsReasoningForNonPCCProviders() {
        XCTAssertThrowsError(
            try ModelConfig.resolve(
                providerFlag: "apple",
                modelFlag: nil,
                baseURLFlag: nil,
                reasoningFlag: "light",
                env: [:]
            )
        ) { error in
            guard case ModelConfigError.reasoningUnsupported(let provider) = error else {
                XCTFail("Expected reasoningUnsupported, got: \(error)")
                return
            }
            XCTAssertEqual(provider, "apple")
        }
    }

    func testResolveRejectsInvalidReasoningLevel() {
        XCTAssertThrowsError(
            try ModelConfig.resolve(
                providerFlag: "apple-pcc",
                modelFlag: nil,
                baseURLFlag: nil,
                reasoningFlag: "maximum",
                env: [:]
            )
        ) { error in
            guard case ModelConfigError.invalidReasoningLevel(let value) = error else {
                XCTFail("Expected invalidReasoningLevel, got: \(error)")
                return
            }
            XCTAssertEqual(value, "maximum")
        }
    }

    func testResolveExperimentalLocalProviders() throws {
        let coreAI = try ModelConfig.resolve(
            providerFlag: "core-ai",
            modelFlag: "qwen3-4b.aimodel",
            baseURLFlag: nil,
            env: [:]
        )
        XCTAssertEqual(coreAI.provider, .coreAI)
        XCTAssertEqual(coreAI.model, "qwen3-4b.aimodel")

        let mlx = try ModelConfig.resolve(
            providerFlag: "mlx-swift-lm",
            modelFlag: "mlx-community/Qwen3-4B-4bit",
            baseURLFlag: nil,
            env: [:]
        )
        XCTAssertEqual(mlx.provider, .mlx)
        XCTAssertEqual(mlx.model, "mlx-community/Qwen3-4B-4bit")
    }

    func testResolveRejectsBaseURLForCodex() {
        XCTAssertThrowsError(
            try ModelConfig.resolve(
                providerFlag: "codex",
                modelFlag: nil,
                baseURLFlag: "http://127.0.0.1:11434",
                env: [:]
            )
        ) { error in
            guard case ModelConfigError.codexDoesNotUseRemoteBaseURL = error else {
                XCTFail("Expected codexDoesNotUseRemoteBaseURL, got: \(error)")
                return
            }
        }
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
            ModelConfigError.invalidProvider("openai-compatible").localizedDescription.contains("codex")
        )
        XCTAssertTrue(
            ModelConfigError.missingModel.localizedDescription.contains("requires a model")
        )
    }
}
