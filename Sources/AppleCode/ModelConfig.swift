import Foundation

enum ProviderKind: String, Codable, Sendable {
    case apple
    case applePCC = "apple-pcc"
    case ollama
    case codex
    case coreAI = "coreai"
    case mlx

    init?(rawCLIValue: String) {
        let normalized = rawCLIValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "apple", "on-device", "ondevice", "foundation", "foundationmodels":
            self = .apple
        case "apple-pcc", "pcc", "private-cloud-compute", "privatecloudcompute":
            self = .applePCC
        case "ollama", "local-ollama":
            self = .ollama
        case "codex", "codex-cli":
            self = .codex
        case "coreai", "core-ai":
            self = .coreAI
        case "mlx", "mlx-swift", "mlx-swift-lm":
            self = .mlx
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .apple:
            return "apple"
        case .applePCC:
            return "apple-pcc"
        case .ollama:
            return "ollama"
        case .codex:
            return "codex"
        case .coreAI:
            return "coreai"
        case .mlx:
            return "mlx"
        }
    }
}

enum ReasoningLevel: String, Codable, Sendable {
    case light
    case moderate
    case deep

    static let allMenuOptions: [ReasoningLevel] = [.light, .moderate, .deep]

    init?(rawCLIValue: String) {
        let normalized = rawCLIValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "light":
            self = .light
        case "moderate", "medium":
            self = .moderate
        case "deep", "high":
            self = .deep
        default:
            return nil
        }
    }
}

struct ModelConfig: Codable, Sendable {
    let provider: ProviderKind
    let model: String?
    let baseURL: String?
    let reasoningLevel: ReasoningLevel?

    init(
        provider: ProviderKind,
        model: String?,
        baseURL: String?,
        reasoningLevel: ReasoningLevel? = nil
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.reasoningLevel = reasoningLevel
    }

    static let appleDefault = ModelConfig(provider: .apple, model: nil, baseURL: nil)
    static let applePCCDefault = ModelConfig(provider: .applePCC, model: nil, baseURL: nil)
    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"
    static let defaultCodexModel = "gpt-5.4"

    var modeLabel: String {
        switch provider {
        case .apple:
            return "on-device"
        case .applePCC:
            return "apple-pcc"
        case .ollama:
            return "ollama"
        case .codex:
            return "codex"
        case .coreAI:
            return "coreai"
        case .mlx:
            return "mlx"
        }
    }

    static func resolve(
        providerFlag: String?,
        modelFlag: String?,
        baseURLFlag: String?,
        reasoningFlag: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ModelConfig {
        let trimmedProvider = providerFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURLFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = reasoningFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningLevel: ReasoningLevel?
        if let value = trimmedReasoning, !value.isEmpty {
            guard let parsed = ReasoningLevel(rawCLIValue: value) else {
                throw ModelConfigError.invalidReasoningLevel(value)
            }
            reasoningLevel = parsed
        } else {
            reasoningLevel = nil
        }

        let provider: ProviderKind
        if let value = trimmedProvider, !value.isEmpty {
            guard let parsed = ProviderKind(rawCLIValue: value) else {
                throw ModelConfigError.invalidProvider(value)
            }
            provider = parsed
        } else if trimmedBaseURL?.isEmpty == false {
            provider = .ollama
        } else if trimmedModel?.isEmpty == false {
            provider = .ollama
        } else {
            provider = .apple
        }

        switch provider {
        case .apple:
            if reasoningLevel != nil {
                throw ModelConfigError.reasoningUnsupported(provider: provider.displayName)
            }
            if (trimmedModel?.isEmpty == false) || (trimmedBaseURL?.isEmpty == false) {
                throw ModelConfigError.appleDoesNotUseRemoteModelFlags
            }
            return .appleDefault

        case .applePCC:
            if (trimmedModel?.isEmpty == false) || (trimmedBaseURL?.isEmpty == false) {
                throw ModelConfigError.appleDoesNotUseRemoteModelFlags
            }
            return ModelConfig(provider: .applePCC, model: nil, baseURL: nil, reasoningLevel: reasoningLevel)

        case .ollama:
            if reasoningLevel != nil {
                throw ModelConfigError.reasoningUnsupported(provider: provider.displayName)
            }
            let effectiveModel = nonEmpty(trimmedModel) ?? nonEmpty(env["OLLAMA_MODEL"])

            let rawBaseURL = nonEmpty(trimmedBaseURL)
                ?? nonEmpty(env["OLLAMA_BASE_URL"])
                ?? defaultOllamaBaseURL
            let normalizedBaseURL = try normalizeBaseURL(rawBaseURL)

            return ModelConfig(
                provider: .ollama,
                model: effectiveModel,
                baseURL: normalizedBaseURL.absoluteString
            )

        case .codex:
            if reasoningLevel != nil {
                throw ModelConfigError.reasoningUnsupported(provider: provider.displayName)
            }
            if trimmedBaseURL?.isEmpty == false {
                throw ModelConfigError.codexDoesNotUseRemoteBaseURL
            }
            return ModelConfig(
                provider: .codex,
                model: nonEmpty(trimmedModel) ?? nonEmpty(env["CODEX_MODEL"]) ?? defaultCodexModel,
                baseURL: nil
            )

        case .coreAI, .mlx:
            if reasoningLevel != nil {
                throw ModelConfigError.reasoningUnsupported(provider: provider.displayName)
            }
            if trimmedBaseURL?.isEmpty == false {
                throw ModelConfigError.localProviderDoesNotUseBaseURL(provider.displayName)
            }
            return ModelConfig(provider: provider, model: nonEmpty(trimmedModel), baseURL: nil)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            return nil
        }
        return v
    }

    static func normalizeBaseURL(_ raw: String) throws -> URL {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            throw ModelConfigError.invalidBaseURL(raw)
        }

        let cleanedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleanedPath.isEmpty {
            components.path = "/" + cleanedPath
        } else {
            components.path = ""
        }

        guard let url = components.url else {
            throw ModelConfigError.invalidBaseURL(raw)
        }
        return url
    }
}

extension URL {
    func appendingOllamaEndpoint(_ endpoint: String) -> URL {
        appendingPathComponent("api").appendingPathComponent(endpoint)
    }
}

enum ModelConfigError: LocalizedError {
    case invalidProvider(String)
    case invalidBaseURL(String)
    case missingModel
    case appleDoesNotUseRemoteModelFlags
    case codexDoesNotUseRemoteBaseURL
    case invalidReasoningLevel(String)
    case reasoningUnsupported(provider: String)
    case localProviderDoesNotUseBaseURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidProvider(let value):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "openai-compatible" {
                return "Provider 'openai-compatible' was removed. Use 'codex', 'ollama' (local), or 'apple' (AFM)."
            }
            return "Invalid provider '\(value)'. Use 'apple', 'apple-pcc', 'ollama', 'codex', 'coreai', or 'mlx'."
        case .invalidBaseURL(let value):
            return "Invalid base URL '\(value)'. Use a valid http or https URL."
        case .missingModel:
            return "Ollama provider requires a model. Set --model or OLLAMA_MODEL."
        case .appleDoesNotUseRemoteModelFlags:
            return "--base-url can only be used with --provider ollama. --model is supported by ollama, codex, coreai, and mlx."
        case .codexDoesNotUseRemoteBaseURL:
            return "--base-url can only be used with --provider ollama; Codex CLI uses your local Codex config."
        case .invalidReasoningLevel(let value):
            return "Invalid reasoning level '\(value)'. Use 'light', 'moderate', or 'deep'."
        case .reasoningUnsupported:
            return "--reasoning is only supported by --provider apple-pcc."
        case .localProviderDoesNotUseBaseURL(let provider):
            return "--base-url is not supported by --provider \(provider)."
        }
    }
}
