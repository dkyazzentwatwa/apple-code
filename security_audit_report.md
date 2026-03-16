# Security Audit Report - apple-code

Date: 2026-03-03
Scope: Full code audit + threat model for local single-user deployment.

## Executive Summary
Major high-risk surfaces were command execution, unrestricted filesystem access, and automatic fallback tool execution. A security policy layer was implemented and integrated across high-risk tools. Secure-by-default behavior is now enforced via a new security profile system with explicit opt-in flags for dangerous behaviors.

## Severity Legend
- Critical: immediate compromise or severe destructive impact likely.
- High: significant confidentiality/integrity risk.
- Medium: meaningful risk with constraints.
- Low: defense-in-depth or limited practical impact.

## Findings

### AC-SEC-001 (High) - Dangerous warned shell commands were previously executed
- Evidence: `Sources/AppleCode/Tools/RunCommandTool.swift`
- Risk: commands like `curl | sh`, recursive deletes, and privileged operations could run when merely flagged as warn.
- Status: Fixed.
- Fix: warned commands are blocked under secure profile unless explicitly opted in with `--dangerous-without-confirm`.

### AC-SEC-002 (High) - Filesystem tools lacked root confinement
- Evidence: `ReadFileTool`, `WriteFileTool`, `EditFileTool`, `ListDirectoryTool`, `SearchFilesTool`, `SearchContentTool`, `CreatePDFTool`.
- Risk: model/tool calls could access paths outside intended workspace.
- Status: Fixed.
- Fix: centralized path policy with canonical/symlink-aware root checks.

### AC-SEC-003 (High) - Automatic fallback could execute side effects
- Evidence: fallback flows in `main.swift`, `REPLLoop.swift`, `CommandFallback.swift`.
- Risk: commands and writes could be auto-triggered after refusal/thin responses.
- Status: Fixed.
- Fix: automatic fallback execution now policy-gated and disabled by default in secure profile.

### AC-SEC-004 (Medium/High) - Web tools could target private/local network hosts
- Evidence: `WebFetchTool`, `WebSearchTool`, `AgentBrowserTool`.
- Risk: local service probing / internal data access.
- Status: Fixed.
- Fix: URL host checks block localhost/private targets by default; optional allow via policy flags.

### AC-SEC-005 (Medium) - Mutating Apple/browser/git actions had no secure-default gate
- Evidence: mutating branches in Notes/Calendar/Reminders/AgentBrowser/Git tools.
- Risk: unintended side effects via model tool routing.
- Status: Fixed.
- Fix: mutating actions require `--dangerous-without-confirm` under secure profile.

### AC-SEC-006 (Medium) - Session/log data stored locally in plaintext
- Evidence: `Session.swift`, `UILogger.swift`.
- Risk: local disclosure if host account or filesystem permissions are weak.
- Status: Open (documented).
- Recommendation: enforce restrictive file permissions and add optional redaction/encryption mode.

## Implemented Changes
1. Added `ToolSafetyPolicy` and `ToolSafety` shared policy runtime (`Sources/AppleCode/ToolSafetyPolicy.swift`).
2. Added CLI and config-level security controls:
- `--security-profile`
- `--allow-path`
- `--allow-host`
- `--allow-private-network`
- `--dangerous-without-confirm`
- `--allow-fallback-execution`
3. Added path confinement checks to filesystem and PDF tools.
4. Added URL host safety checks to web/browser entry points.
5. Added secure-default blocking for dangerous command warnings and mutating operations.
6. Disabled automatic fallback execution by default under secure profile.
7. Added/updated unit tests for policy behavior.

## Testing
- Added `Tests/AppleCodeTests/SecurityPolicyTests.swift`.
- Updated existing test classes to set explicit test policy where needed.
- Existing unrelated baseline failures in `ModelConfigTests` may remain and should be tracked separately.

## Residual Risk / Next Actions
1. Add DNS-resolution-based private IP detection for domain targets.
2. Harden `~/.apple-code` file permissions to least privilege.
3. Add redaction/retention controls for transcripts and logs.
4. Add explicit REPL confirmation UX for dangerous operations.
