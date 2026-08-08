import Foundation
import FoundationModels

struct ModelCapabilities: Sendable, Equatable {
    let contextSize: Int
    let supportsStreaming: Bool
    let supportsReasoning: Bool
    let supportsVision: Bool
    let isExperimental: Bool
    let quotaStatus: String?
    let availabilitySummary: String

    static func resolved(for config: ModelConfig) -> ModelCapabilities {
        switch config.provider {
        case .apple:
            let model = SystemLanguageModel.default
            return ModelCapabilities(
                contextSize: model.contextSize,
                supportsStreaming: true,
                supportsReasoning: false,
                supportsVision: false,
                isExperimental: false,
                quotaStatus: nil,
                availabilitySummary: "\(model.availability)"
            )

        case .applePCC:
            return ModelCapabilities(
                contextSize: 32_768,
                supportsStreaming: true,
                supportsReasoning: true,
                supportsVision: false,
                isExperimental: true,
                quotaStatus: "Requires PCC-enabled FoundationModels SDK/runtime; quota status unavailable in this build.",
                availabilitySummary: "pending SDK support"
            )

        case .ollama:
            return ModelCapabilities(
                contextSize: 8_192,
                supportsStreaming: true,
                supportsReasoning: false,
                supportsVision: false,
                isExperimental: false,
                quotaStatus: nil,
                availabilitySummary: "local service"
            )

        case .codex:
            return ModelCapabilities(
                contextSize: 32_000,
                supportsStreaming: true,
                supportsReasoning: false,
                supportsVision: false,
                isExperimental: false,
                quotaStatus: nil,
                availabilitySummary: "local Codex CLI"
            )

        case .coreAI:
            return ModelCapabilities(
                contextSize: 8_192,
                supportsStreaming: true,
                supportsReasoning: false,
                supportsVision: false,
                isExperimental: true,
                quotaStatus: nil,
                availabilitySummary: "requires macOS 27+, Xcode 27+, and apple/coreai-models integration"
            )

        case .mlx:
            return ModelCapabilities(
                contextSize: 8_192,
                supportsStreaming: true,
                supportsReasoning: false,
                supportsVision: false,
                isExperimental: true,
                quotaStatus: nil,
                availabilitySummary: "requires mlx-swift-lm integration"
            )
        }
    }
}
