import Foundation
import Darwin

enum SecurityProfile: String, Codable, Sendable {
    case secure
    case balanced
    case compatibility

    static func parse(_ raw: String?) -> SecurityProfile? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "secure", "strict", "safe":
            return .secure
        case "balanced", "default":
            return .balanced
        case "compatibility", "compat", "legacy":
            return .compatibility
        default:
            return nil
        }
    }

    var defaultAllowPrivateNetwork: Bool {
        switch self {
        case .secure, .balanced:
            return false
        case .compatibility:
            return true
        }
    }

    var defaultAllowDangerousWithoutConfirmation: Bool {
        switch self {
        case .secure:
            return false
        case .balanced, .compatibility:
            return true
        }
    }

    var defaultAllowAutomaticFallbackExecution: Bool {
        switch self {
        case .secure:
            return false
        case .balanced, .compatibility:
            return true
        }
    }
}

struct PathSafetyCheckResult: Sendable {
    let allowed: Bool
    let resolvedPath: String
    let reason: String?
}

struct URLSafetyCheckResult: Sendable {
    let allowed: Bool
    let reason: String?
}

struct ToolSafetyPolicy: Sendable {
    let profile: SecurityProfile
    let allowedRoots: [String]
    let allowedHosts: [String]
    let allowPrivateNetwork: Bool
    let allowDangerousWithoutConfirmation: Bool
    let allowAutomaticFallbackExecution: Bool

    static func make(
        profile: SecurityProfile,
        workingDirectory: String,
        additionalAllowedRoots: [String],
        allowedHosts: [String],
        allowPrivateNetwork: Bool?,
        allowDangerousWithoutConfirmation: Bool?,
        allowAutomaticFallbackExecution: Bool?
    ) -> ToolSafetyPolicy {
        var roots = [workingDirectory] + additionalAllowedRoots
        roots = roots
            .map { canonicalPath($0, forWrite: false) }
            .filter { !$0.isEmpty }
        roots = Array(Set(roots)).sorted()

        let hosts = allowedHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return ToolSafetyPolicy(
            profile: profile,
            allowedRoots: roots,
            allowedHosts: Array(Set(hosts)).sorted(),
            allowPrivateNetwork: allowPrivateNetwork ?? profile.defaultAllowPrivateNetwork,
            allowDangerousWithoutConfirmation: allowDangerousWithoutConfirmation ?? profile.defaultAllowDangerousWithoutConfirmation,
            allowAutomaticFallbackExecution: allowAutomaticFallbackExecution ?? profile.defaultAllowAutomaticFallbackExecution
        )
    }

    func checkPath(_ rawPath: String, forWrite: Bool) -> PathSafetyCheckResult {
        let resolved = Self.canonicalPath(rawPath, forWrite: forWrite)
        guard !resolved.isEmpty else {
            return PathSafetyCheckResult(
                allowed: false,
                resolvedPath: rawPath,
                reason: "invalid path"
            )
        }
        guard !allowedRoots.isEmpty else {
            return PathSafetyCheckResult(allowed: true, resolvedPath: resolved, reason: nil)
        }

        for root in allowedRoots {
            if resolved == root || resolved.hasPrefix(root + "/") {
                return PathSafetyCheckResult(allowed: true, resolvedPath: resolved, reason: nil)
            }
        }

        return PathSafetyCheckResult(
            allowed: false,
            resolvedPath: resolved,
            reason: "outside allowed roots"
        )
    }

    func checkURL(_ url: URL) -> URLSafetyCheckResult {
        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else {
            return URLSafetyCheckResult(allowed: false, reason: "missing host")
        }

        if !allowedHosts.isEmpty {
            let hostAllowed = allowedHosts.contains { allowed in
                host == allowed || host.hasSuffix("." + allowed)
            }
            if !hostAllowed {
                return URLSafetyCheckResult(allowed: false, reason: "host not in allowlist")
            }
        }

        if !allowPrivateNetwork && Self.isPrivateHost(host) {
            return URLSafetyCheckResult(allowed: false, reason: "private/local network targets are blocked")
        }

        return URLSafetyCheckResult(allowed: true, reason: nil)
    }

    static func canonicalPath(_ rawPath: String, forWrite: Bool) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let absolute = (expanded as NSString).isAbsolutePath
            ? expanded
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
        let standardized = URL(fileURLWithPath: absolute).standardizedFileURL
        if !forWrite {
            return standardized.resolvingSymlinksInPath().path
        }

        // For writes, resolve the parent directory to avoid symlink escapes.
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        let final = parent.appendingPathComponent(standardized.lastPathComponent)
        return final.standardizedFileURL.path
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower == "0.0.0.0" || lower == "::1" {
            return true
        }
        if lower.hasSuffix(".local") {
            return true
        }

        if let ipv4 = parseIPv4(lower) {
            // 10.0.0.0/8
            if (ipv4 & 0xFF00_0000) == 0x0A00_0000 { return true }
            // 127.0.0.0/8
            if (ipv4 & 0xFF00_0000) == 0x7F00_0000 { return true }
            // 169.254.0.0/16
            if (ipv4 & 0xFFFF_0000) == 0xA9FE_0000 { return true }
            // 172.16.0.0/12
            if (ipv4 & 0xFFF0_0000) == 0xAC10_0000 { return true }
            // 192.168.0.0/16
            if (ipv4 & 0xFFFF_0000) == 0xC0A8_0000 { return true }
        }

        if let ipv6 = parseIPv6(lower) {
            // loopback ::1
            if ipv6.dropLast().allSatisfy({ $0 == 0 }) && ipv6.last == 1 {
                return true
            }
            // unique local fc00::/7
            if (ipv6[0] & 0xFE) == 0xFC {
                return true
            }
            // link-local fe80::/10
            if ipv6[0] == 0xFE && (ipv6[1] & 0xC0) == 0x80 {
                return true
            }
        }

        return false
    }

    private static func parseIPv4(_ host: String) -> UInt32? {
        var addr = in_addr()
        let ok = host.withCString { inet_pton(AF_INET, $0, &addr) }
        guard ok == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var addr = in6_addr()
        let ok = host.withCString { inet_pton(AF_INET6, $0, &addr) }
        guard ok == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }
}

final class ToolSafety: @unchecked Sendable {
    static let shared = ToolSafety()

    private let lock = NSLock()
    private var policy: ToolSafetyPolicy

    private init() {
        let cwd = FileManager.default.currentDirectoryPath
        policy = ToolSafetyPolicy.make(
            profile: .secure,
            workingDirectory: cwd,
            additionalAllowedRoots: [],
            allowedHosts: [],
            allowPrivateNetwork: nil,
            allowDangerousWithoutConfirmation: nil,
            allowAutomaticFallbackExecution: nil
        )
    }

    func configure(_ policy: ToolSafetyPolicy) {
        lock.lock()
        self.policy = policy
        lock.unlock()
    }

    func currentPolicy() -> ToolSafetyPolicy {
        lock.lock()
        let snapshot = policy
        lock.unlock()
        return snapshot
    }

    func updateWorkingDirectory(_ workingDirectory: String) {
        lock.lock()
        let updated = ToolSafetyPolicy.make(
            profile: policy.profile,
            workingDirectory: workingDirectory,
            additionalAllowedRoots: policy.allowedRoots,
            allowedHosts: policy.allowedHosts,
            allowPrivateNetwork: policy.allowPrivateNetwork,
            allowDangerousWithoutConfirmation: policy.allowDangerousWithoutConfirmation,
            allowAutomaticFallbackExecution: policy.allowAutomaticFallbackExecution
        )
        policy = updated
        lock.unlock()
    }

    func checkPath(_ rawPath: String, forWrite: Bool) -> PathSafetyCheckResult {
        currentPolicy().checkPath(rawPath, forWrite: forWrite)
    }

    func checkURL(_ url: URL) -> URLSafetyCheckResult {
        currentPolicy().checkURL(url)
    }
}
