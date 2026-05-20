import Foundation

enum ProviderKind: String, Codable, Sendable {
    case apple
    case ollama
    case codex

    init?(rawCLIValue: String) {
        let normalized = rawCLIValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "apple", "on-device", "ondevice", "foundation", "foundationmodels":
            self = .apple
        case "ollama", "local-ollama":
            self = .ollama
        case "codex", "codex-cli":
            self = .codex
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .apple:
            return "apple"
        case .ollama:
            return "ollama"
        case .codex:
            return "codex"
        }
    }
}

struct ModelConfig: Codable, Sendable {
    let provider: ProviderKind
    let model: String?
    let baseURL: String?

    static let appleDefault = ModelConfig(provider: .apple, model: nil, baseURL: nil)
    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"

    var modeLabel: String {
        switch provider {
        case .apple:
            return "on-device"
        case .ollama:
            return "ollama"
        case .codex:
            return "codex"
        }
    }

    static func resolve(
        providerFlag: String?,
        modelFlag: String?,
        baseURLFlag: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ModelConfig {
        let trimmedProvider = providerFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelFlag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURLFlag?.trimmingCharacters(in: .whitespacesAndNewlines)

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
            if (trimmedModel?.isEmpty == false) || (trimmedBaseURL?.isEmpty == false) {
                throw ModelConfigError.appleDoesNotUseRemoteModelFlags
            }
            return .appleDefault

        case .ollama:
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
            if trimmedBaseURL?.isEmpty == false {
                throw ModelConfigError.codexDoesNotUseRemoteBaseURL
            }
            return ModelConfig(
                provider: .codex,
                model: nonEmpty(trimmedModel) ?? nonEmpty(env["CODEX_MODEL"]),
                baseURL: nil
            )
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

    var errorDescription: String? {
        switch self {
        case .invalidProvider(let value):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "openai-compatible" {
                return "Provider 'openai-compatible' was removed. Use 'codex', 'ollama' (local), or 'apple' (AFM)."
            }
            return "Invalid provider '\(value)'. Use 'apple', 'ollama', or 'codex'."
        case .invalidBaseURL(let value):
            return "Invalid base URL '\(value)'. Use a valid http or https URL."
        case .missingModel:
            return "Ollama provider requires a model. Set --model or OLLAMA_MODEL."
        case .appleDoesNotUseRemoteModelFlags:
            return "--base-url can only be used with --provider ollama. --model is supported by ollama and codex."
        case .codexDoesNotUseRemoteBaseURL:
            return "--base-url can only be used with --provider ollama; Codex CLI uses your local Codex config."
        }
    }
}
