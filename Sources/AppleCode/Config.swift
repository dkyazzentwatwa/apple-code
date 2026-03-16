import Foundation

/// Simple key=value config reader for ~/.apple-code/config and ./.apple-code
struct AppConfig {
    var provider: String?
    var model: String?
    var baseURL: String?
    var theme: String?
    var uiMode: String?
    var systemPrompt: String?
    var securityProfile: String?
    var allowPaths: [String]?
    var allowHosts: [String]?
    var allowPrivateNetwork: Bool?
    var dangerousWithoutConfirm: Bool?
    var allowFallbackExecution: Bool?

    static let empty = AppConfig()

    /// Loads config with project-level override of global config.
    /// Search order (later wins): global → project
    static func load(workingDir: String) -> AppConfig {
        var config = AppConfig.empty

        // 1. Global config: ~/.apple-code/config
        let home = FileManager.default.homeDirectoryForCurrentUser
        let globalPath = home
            .appendingPathComponent(".apple-code")
            .appendingPathComponent("config")
            .path
        if let global = parse(filePath: globalPath) {
            config.merge(global)
        }

        // 2. Project config: <CWD>/.apple-code
        let projectPath = (workingDir as NSString).appendingPathComponent(".apple-code")
        if let project = parse(filePath: projectPath) {
            config.merge(project)
        }

        return config
    }

    /// Merge another config on top of this one; non-nil values win.
    mutating func merge(_ other: AppConfig) {
        if let v = other.provider    { provider    = v }
        if let v = other.model       { model       = v }
        if let v = other.baseURL     { baseURL     = v }
        if let v = other.theme       { theme       = v }
        if let v = other.uiMode      { uiMode      = v }
        if let v = other.systemPrompt { systemPrompt = v }
        if let v = other.securityProfile { securityProfile = v }
        if let v = other.allowPaths  { allowPaths  = v }
        if let v = other.allowHosts  { allowHosts  = v }
        if let v = other.allowPrivateNetwork { allowPrivateNetwork = v }
        if let v = other.dangerousWithoutConfirm { dangerousWithoutConfirm = v }
        if let v = other.allowFallbackExecution { allowFallbackExecution = v }
    }

    /// Parse a key=value config file. Lines starting with # are comments.
    static func parse(filePath: String) -> AppConfig? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        var config = AppConfig()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = trimmed[eqRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !key.isEmpty, !value.isEmpty else { continue }
            switch key {
            case "provider":         config.provider     = value
            case "model":            config.model        = value
            case "base_url", "baseurl": config.baseURL   = value
            case "theme":            config.theme        = value
            case "ui", "ui_mode":   config.uiMode       = value
            case "system_prompt":    config.systemPrompt = value
            case "security_profile": config.securityProfile = value
            case "allow_paths":
                let values = splitCSV(value)
                if !values.isEmpty { config.allowPaths = values }
            case "allow_hosts":
                let values = splitCSV(value)
                if !values.isEmpty { config.allowHosts = values }
            case "allow_private_network":
                config.allowPrivateNetwork = parseBool(value)
            case "dangerous_without_confirm", "dangerous_without_confirmation":
                config.dangerousWithoutConfirm = parseBool(value)
            case "allow_fallback_execution", "automatic_fallback_execution":
                config.allowFallbackExecution = parseBool(value)
            default: break
            }
        }
        return config
    }

    private static func splitCSV(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "y", "on":
            return true
        case "false", "0", "no", "n", "off":
            return false
        default:
            return nil
        }
    }

    /// Create the global config directory if it doesn't exist.
    static func ensureConfigDir() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".apple-code")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
