import Foundation

struct RuntimeSecurityCLIOverrides: Sendable {
    var securityProfile: String?
    var allowPaths: [String] = []
    var allowHosts: [String] = []
    var allowPrivateNetwork: Bool?
    var dangerousWithoutConfirm: Bool?
    var allowFallbackExecution: Bool?
    var privacyRedaction: String?
}

struct RuntimeSecurityOptions: Sendable {
    let profile: SecurityProfile
    let additionalAllowedRoots: [String]
    let allowedHosts: [String]
    let allowPrivateNetwork: Bool?
    let allowDangerousWithoutConfirmation: Bool?
    let allowAutomaticFallbackExecution: Bool?
    let privacyRedactionMode: PrivacyRedactionMode

    static func resolve(
        config: AppConfig,
        cli: RuntimeSecurityCLIOverrides
    ) throws -> RuntimeSecurityOptions {
        let profileRaw = cli.securityProfile ?? config.securityProfile
        let profile = SecurityProfile.parse(profileRaw) ?? .secure
        if let profileRaw, SecurityProfile.parse(profileRaw) == nil {
            throw RuntimeSecurityOptionsError.invalidSecurityProfile(profileRaw)
        }

        let redactionRaw = cli.privacyRedaction ?? config.privacyRedaction
        let redaction = PrivacyRedactionMode.parse(redactionRaw) ?? .logs
        if let redactionRaw, PrivacyRedactionMode.parse(redactionRaw) == nil {
            throw RuntimeSecurityOptionsError.invalidPrivacyRedaction(redactionRaw)
        }

        return RuntimeSecurityOptions(
            profile: profile,
            additionalAllowedRoots: merged(config.allowPaths, cli.allowPaths),
            allowedHosts: merged(config.allowHosts, cli.allowHosts),
            allowPrivateNetwork: cli.allowPrivateNetwork ?? config.allowPrivateNetwork,
            allowDangerousWithoutConfirmation: cli.dangerousWithoutConfirm ?? config.dangerousWithoutConfirm,
            allowAutomaticFallbackExecution: cli.allowFallbackExecution ?? config.allowFallbackExecution,
            privacyRedactionMode: redaction
        )
    }

    func configureRuntime(workingDirectory: String) {
        ToolSafety.shared.configure(
            ToolSafetyPolicy.make(
                profile: profile,
                workingDirectory: workingDirectory,
                additionalAllowedRoots: additionalAllowedRoots,
                allowedHosts: allowedHosts,
                allowPrivateNetwork: allowPrivateNetwork,
                allowDangerousWithoutConfirmation: allowDangerousWithoutConfirmation,
                allowAutomaticFallbackExecution: allowAutomaticFallbackExecution
            )
        )
        PrivacyRedactor.shared.configure(mode: privacyRedactionMode)
    }

    private static func merged(_ configValues: [String]?, _ cliValues: [String]) -> [String] {
        var values = configValues ?? []
        values.append(contentsOf: cliValues)
        return Array(Set(values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }
}

enum RuntimeSecurityOptionsError: LocalizedError {
    case invalidSecurityProfile(String)
    case invalidPrivacyRedaction(String)

    var errorDescription: String? {
        switch self {
        case .invalidSecurityProfile(let value):
            return "Invalid security profile '\(value)'. Use secure, balanced, or compatibility."
        case .invalidPrivacyRedaction(let value):
            return "Invalid privacy redaction mode '\(value)'. Use off, logs, transcripts, or all."
        }
    }
}
