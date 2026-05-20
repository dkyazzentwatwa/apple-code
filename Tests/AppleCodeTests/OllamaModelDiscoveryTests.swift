import XCTest
@testable import apple_code

final class OllamaModelDiscoveryTests: XCTestCase {
    func testRecommendedQwenModelsIncludesExpectedOrder() {
        XCTAssertEqual(
            OllamaModelDiscovery.recommendedQwenModels,
            ["qwen3.5:9b", "qwen3.5:4b", "qwen3.5:2b", "qwen3.5:0.8b"]
        )
    }

    func testPreferredDefaultModelFallbacks() {
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["abc", "def"]), "abc")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5:4b", "qwen3.5:9b"]), "qwen3.5:9b")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["abc", "qwen2.5-coder:7b"]), "qwen2.5-coder:7b")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5:0.8b"]), "qwen3.5:0.8b")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5 4b"]), "qwen3.5 4b")
    }

    func testDiscoveryMessageExplainsServerDownWithCliModels() {
        let message = OllamaModelDiscovery.discoveryMessage(
            cliModels: ["qwen3.5:9b"],
            apiReachable: false
        )

        XCTAssertTrue(message.contains("ollama list"))
        XCTAssertTrue(message.contains("ollama serve"))
    }

    func testInstalledModelsReturnsArrayWithoutThrowing() async {
        let result = await OllamaModelDiscovery.installedModels(baseURL: URL(string: "http://127.0.0.1:65535")!)
        XCTAssertNotNil(result)
    }
}
