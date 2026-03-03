import XCTest
@testable import apple_code

final class OllamaModelDiscoveryTests: XCTestCase {
    func testRecommendedQwenModelsIncludesExpectedOrder() {
        XCTAssertEqual(
            OllamaModelDiscovery.recommendedQwenModels,
            ["qwen3.5:4b", "qwen3.5:2b", "qwen3.5:0.8b"]
        )
    }

    func testPreferredDefaultModelFallbacks() {
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["abc", "def"]), "abc")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5:0.8b"]), "qwen3.5:0.8b")
        XCTAssertEqual(OllamaModelDiscovery.preferredDefaultModel(from: ["qwen3.5 4b"]), "qwen3.5 4b")
    }

    func testInstalledModelsReturnsArrayWithoutThrowing() async {
        let result = await OllamaModelDiscovery.installedModels(baseURL: URL(string: "http://127.0.0.1:65535")!)
        XCTAssertNotNil(result)
    }
}
