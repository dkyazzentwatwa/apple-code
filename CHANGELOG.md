# Changelog

All notable changes to apple-code are documented in this file.

## [Unreleased]

### Fixed
- **Ollama URL contract tests** — `ModelConfigTests` now assert native Ollama base URLs without an implicit `/v1` suffix, matching the runtime's `/api/chat` and `/api/tags` requests.

## [v0.2.0] — 2026-03-04

### Added
- **EditFileTool** — Find-and-replace editing for files with exact string validation. Supports deletion by replacing with empty string. Returns line number and delta for precise feedback.
- **GitTool** — First-class git integration with actions: `status`, `diff`, `log`, `commit` (with staged check), `stash` (push/pop/list), `branch_list`, `blame`. Output capped for context efficiency.
- **Natural language git routing** — Prompts like "show me the diff", "what's changed", "recent commits" now correctly route to GitTool instead of file tools.
- **Config file support** — Global `~/.apple-code/config` and project-level `./.apple-code` with key=value format. Supports: `provider`, `model`, `base_url`, `theme`, `ui_mode`, `system_prompt`. CLI flags override config.
- **TokenBudgetManager** — Provider-aware token budgets (AFM ~4096, Ollama ~8192). Rolling-window pruning keeps first message as anchor. Accurate context meter.
- **`/compact` command** — Summarize old conversation turns to free context window for long sessions. Uses secondary model call to generate compact summary.
- **Ctrl+C interrupt** — Cancel ongoing generation with Ctrl+C. SIGINT handler cooperatively cancels task and shows "Generation cancelled" message.
- **Project context file** — Auto-load `APPLE-CODE.md` (or `CLAUDE.md`) from working directory (8000 char limit) and prepend to system instructions. Project personality support.
- **RunCommandTool improvements** — Regex-based command risk classification (hard-block vs warn tiers). Dangerous ops logged to `~/.apple-code/command_audit.log`. Accurate blocklist: `rm -rf /path`, `mkfs`, `dd if=`, `shutdown`, `reboot`, fork bombs.
- **Destructive operation confirmations** — WriteFileTool warns when overwriting existing files. Confirmation prompts for risky shell commands. Audit trail for compliance.
- **APPLE-CODE.md example** — Minimal project context file shipped in repo root (~400 chars) covering key files, tool-add pattern, conventions, build/install.
- **Swift 6 strict concurrency support** — `ToolsBag: @unchecked Sendable` wrapper and top-level `runGenerationTask()` function to handle inout region isolation.

### Fixed
- **Provider switch bug** — Base URL normalization was appending `/v1` suffix (OpenAI convention) for Ollama, causing 404 errors. Now correctly omits path for Ollama (client appends `/api/chat`).
- **Git intent routing** — "show me the diff for X" previously matched broad "show me the" substring and routed to file tools. Now checks git intent before file intent. Expanded natural language triggers: `diff`, `blame`, `commit`, `stash`, `branch`, `what changed`, `recent commits`, etc.
- **EditFileTool newString bug** — `requiredString()` rejected empty strings (calling `optionalString` which returns nil). Now correctly allows empty newString for deletion operations.
- **Dynamic instructions** — Converted static instructions to `buildInstructions()` closure. `/cd` now properly reloads project context file in new directory.

### Changed
- **ModelClient recreation** — Model client is now freshly created before each generation, ensuring provider/config switches take immediate effect.
- **Help text** — Updated usage docs to reflect config file loading, Ctrl+C, `/compact`, and project context file features.
- **Expanded test coverage** — New tests for EditTool, GitTool, AppConfig, TokenBudgetManager, RunCommandRisk, ProjectContext. Total test suite: 84 tests, all passing, 80% gate maintained.

### Technical
- `Sources/AppleCode/Tools/EditFileTool.swift` — ~120 lines
- `Sources/AppleCode/Tools/GitTool.swift` — ~100 lines
- `Sources/AppleCode/Config.swift` — ~150 lines (new)
- `Sources/AppleCode/TokenBudgetManager.swift` — ~200 lines (new)
- `Sources/AppleCode/ModelConfig.swift` — normalizeBaseURL fix removes `/v1` defaulting
- `Sources/AppleCode/REPLLoop.swift` — SIGINT handler, GenerationInterrupt, dynamic instructions, /compact handler, project context loading
- `Sources/AppleCode/main.swift` — Config loading, expanded wantsGit routing, EditFileTool + GitTool integration
- `Sources/AppleCode/ToolBridge.swift` — editFile and git schema + invoke cases
- `Sources/AppleCode/CLICommands.swift` — .compact command case
- `Tests/AppleCodeTests/NewFeaturesTests.swift` — 84 new test cases

---

## [v0.1.0] — 2026-02-XX

Initial public release (30+ stars on day one). Features: AFM + Ollama support, 14 tools, 6 TUI themes, framed/classic UI, session persistence, REPL commands, smart fallback handlers, 80% test coverage.
