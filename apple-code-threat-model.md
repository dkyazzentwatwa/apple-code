# apple-code Threat Model

## Scope
- Repository: `apple-code`
- Runtime: local macOS CLI assistant with tool execution
- Primary context: local single-user developer workstation

## System Model
- Entrypoints: one-shot CLI and interactive REPL in `Sources/AppleCode/main.swift` and `Sources/AppleCode/REPLLoop.swift`.
- Tool execution layer: `ToolBridge` dispatches model tool calls into concrete tools.
- High-risk tools:
  - Shell execution: `RunCommandTool`
  - Filesystem mutation: `WriteFileTool`, `EditFileTool`, `CreatePDFTool`
  - Network/browser: `WebFetchTool`, `WebSearchTool`, `AgentBrowserTool`
  - Apple app integrations: `NotesTool`, `CalendarTool`, `RemindersTool`, `MailTool`, `MessagesTool`
- Persistence:
  - Session transcripts in `~/.apple-code/sessions`
  - CLI logs in `~/.apple-code/logs`

## Assets
- Local source code and repository contents.
- Local secrets/tokens in files and shell environment.
- Apple app data (Notes, Mail, Calendar, Reminders, Messages).
- Session transcripts and logs containing user/model/tool content.
- Host integrity and availability.

## Trust Boundaries
- User input -> LLM output/tool calls.
- LLM tool-call JSON -> `ToolBridge` invocation.
- CLI process -> local shell (`/bin/zsh`).
- CLI process -> local filesystem.
- CLI process -> Apple app automation and Messages DB.
- CLI process -> outbound HTTP(S) network.

## Attacker Goals
- Exfiltrate local sensitive data via tool execution.
- Trigger destructive local actions (file overwrite/delete, dangerous shell ops).
- Abuse fallback logic to execute commands without explicit user intent.
- Reach local/private network services through tool-mediated requests.
- Persist sensitive data in logs/transcripts for later collection.

## Prioritized Threats

### T1: Prompt-induced command execution
- Path: untrusted prompt -> model tool call / fallback -> `runCommand`.
- Impact: high (local command execution).
- Existing control: regex-based hard blocklist and timeouts.
- Implemented mitigation: warned dangerous commands are blocked by default under secure profile and require explicit opt-in (`--dangerous-without-confirm`).

### T2: Arbitrary filesystem read/write outside project scope
- Path: model tool call with absolute/relative path -> file tools.
- Impact: high (data exfiltration or corruption).
- Existing control: none previously.
- Implemented mitigation: policy-enforced allowed roots with canonical path/symlink checks for read/write/edit/list/search/PDF tools.

### T3: Automatic fallback side effects
- Path: refusal/thin response fallback triggers tool execution automatically.
- Impact: high (unexpected command execution/writes).
- Existing control: intent heuristics.
- Implemented mitigation: automatic fallback execution disabled by default in secure profile; explicit opt-in via `--allow-fallback-execution`.

### T4: Private-network/localhost web access
- Path: `webFetch`/`webSearch`/`agentBrowser open` to local/private targets.
- Impact: medium-high (local service probing/data exposure).
- Existing control: scheme validation only.
- Implemented mitigation: private/local host blocking by default in secure profile; optional override via `--allow-private-network`; optional host allowlist (`--allow-host`).

### T5: Mutating Apple/browser/git actions without hardened gate
- Path: tool action dispatch to mutating operations.
- Impact: medium-high.
- Existing control: none previously.
- Implemented mitigation: mutating Notes/Calendar/Reminders/browser-interaction/git-mutate actions blocked under secure profile unless `--dangerous-without-confirm` is set.

### T6: Sensitive transcript/log persistence
- Path: local session/log writes to `~/.apple-code`.
- Impact: medium.
- Existing control: local filesystem permissions only.
- Mitigation status: partially mitigated (risk documented). Additional hardening suggested: stricter file permission mode, optional redaction/encryption.

## Residual Risks
- Prompt injection remains possible in principle where user requests broad automation.
- Hostname allowlist does not currently resolve DNS to detect private IP after domain resolution.
- Transcript/log privacy still depends on host user account security and file permissions.

## Recommended Next Hardening Steps
1. Add DNS/IP post-resolution validation for network tools.
2. Enforce restrictive file modes (0600) on session and log files.
3. Add optional transcript/log redaction for tool outputs.
4. Add explicit interactive confirmation UX for high-risk actions in REPL.
