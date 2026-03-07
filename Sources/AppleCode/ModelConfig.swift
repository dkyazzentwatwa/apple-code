import Foundation

enum ProviderKind: String, Codable, Sendable {
    case apple
    case ollama

    init?(rawCLIValue: String) {
        let normalized = rawCLIValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "apple", "on-device", "ondevice", "foundation", "foundationmodels":
            self = .apple
        case "ollama", "local-ollama":
            self = .ollama
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
        }
    }
}

struct ModelConfig: Codable, Sendable {
    let provider: ProviderKind
    let model: String?
    let baseURL: String?

    static let appleDefault = ModelConfig(provider: .apple, model: nil, baseURL: nil)

    var modeLabel: String {
        switch provider {
        case .apple:
            return "on-device"
        case .ollama:
            return "ollama"
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
        } else if (trimmedModel?.isEmpty == false) || (trimmedBaseURL?.isEmpty == false) {
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
            guard effectiveModel != nil else {
                throw ModelConfigError.missingModel
            }

            let rawBaseURL = nonEmpty(trimmedBaseURL)
                ?? nonEmpty(env["OLLAMA_BASE_URL"])
                ?? "http://127.0.0.1:11434"
            let normalizedBaseURL = try normalizeBaseURL(rawBaseURL)

            return ModelConfig(
                provider: .ollama,
                model: effectiveModel,
                baseURL: normalizedBaseURL.absoluteString
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

enum ModelConfigError: LocalizedError {
    case invalidProvider(String)
    case invalidBaseURL(String)
    case missingModel
    case appleDoesNotUseRemoteModelFlags

    var errorDescription: String? {
        switch self {
        case .invalidProvider(let value):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "openai-compatible" {
                return "Provider 'openai-compatible' was removed. Use 'ollama' (local) or 'apple' (AFM)."
            }
            return "Invalid provider '\(value)'. Use 'apple' or 'ollama'."
        case .invalidBaseURL(let value):
            return "Invalid base URL '\(value)'. Use a valid http or https URL."
        case .missingModel:
            return "Ollama provider requires a model. Set --model or OLLAMA_MODEL."
        case .appleDoesNotUseRemoteModelFlags:
            return "--model/--base-url can only be used with --provider ollama."
        }
    }
}
