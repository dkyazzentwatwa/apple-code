# Plan: Apple Foundation Models Connector ("apple-code")

## Context

Apple Flow currently supports 4 connectors (codex-cli, claude-cli, cline, codex-app-server), all of which require network access and API keys. With macOS 26 on Apple Silicon, Apple's FoundationModels framework provides an on-device ~3B parameter model with native tool calling. This plan adds a new `"afm"` connector that uses a Swift CLI tool (`apple-code`) to provide a fully local, private, zero-latency AI agent with file and command tools — no API keys, no network, no cost.

The architecture mirrors `codex exec` / `claude -p`: a Swift binary handles the agent loop + tool calling natively, and a Python connector manages it as a subprocess.

## Architecture

```
iMessage → Orchestrator → AfmConnector (Python)
                              ↓
                         subprocess.run(["apple-code", "--cwd", workspace, prompt])
                              ↓
                         apple-code (Swift CLI)
                              ↓
                         LanguageModelSession(tools: [...])
                              ↓ (native agent loop)
                         ReadFile / WriteFile / RunCommand / ListDir / Search
                              ↓
                         stdout → response text
```

## Part 1: Swift CLI (`apple-code`) — Can Be Built as a Standalone Project

### Package Structure

```
apple-code/
  Package.swift                          # SPM package, macOS 26+, FoundationModels
  Sources/AppleCode/
    main.swift                           # CLI entry: parse args, create session, respond, print
    Tools/
      ReadFileTool.swift                 # Read file contents (truncate at 50KB)
      WriteFileTool.swift                # Write/create files, create intermediate dirs
      ListDirectoryTool.swift            # List dir contents (recursive option)
      RunCommandTool.swift               # Execute shell cmd (/bin/zsh -c), 30s timeout, 100KB cap
      SearchFilesTool.swift              # Glob-based file search (limit 200 results)
      SearchContentTool.swift            # Grep-like content search (limit 100 matches)
```

### Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "apple-code",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "apple-code",
            path: "Sources/AppleCode"
        )
    ]
)
```

### CLI Interface (mimics `codex exec` / `claude -p`)

```
apple-code [prompt]              # positional prompt (or pipe via stdin for long prompts)
  --system "..."                 # system instructions (SOUL.md content)
  --cwd /path/to/workspace       # working directory for all tool operations
  --timeout 120                  # max seconds (default: 120)
```

### main.swift — Entry Point

Flow:
1. Parse arguments (prompt from positional arg or stdin, --system, --cwd, --timeout)
2. If `--cwd` provided, `chdir()` to that directory
3. Construct array of `Tool` instances
4. Build system instructions string from `--system` flag
5. Create `LanguageModelSession(tools: [...], instructions: { systemInstructions })`
6. Call `try await session.respond(to: prompt)`
7. Print response text to stdout
8. Exit 0 on success, exit 1 on error (error message on stderr)

### Tool Definitions

Each tool follows the `Tool` protocol. All file/directory tools scope operations relative to the cwd.

**ReadFileTool:**
```swift
final class ReadFileTool: Tool {
    let name = "readFile"
    let description = "Read the contents of a file at the given path."

    @Generable
    struct Arguments {
        @Guide(description: "File path relative to working directory")
        let path: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let content = try String(contentsOfFile: arguments.path, encoding: .utf8)
        return ToolOutput(String(content.prefix(50_000)))
    }
}
```

**WriteFileTool:** Arguments: `path: String`, `content: String`. Creates intermediate directories if needed. Returns confirmation with bytes written.

**ListDirectoryTool:** Arguments: `path: String` (default: "."), `recursive: Bool` (default: false). Returns newline-separated file listing with types (file/dir).

**RunCommandTool:** Arguments: `command: String`, `timeout: Int` (default: 30). Spawns `/bin/zsh -c` and captures stdout+stderr. 30s per-command timeout, 100KB output cap. Basic blocklist for destructive patterns.

**SearchFilesTool:** Arguments: `pattern: String`, `path: String` (default: "."). Glob matching via `fnmatch`. Returns matching paths (limit 200).

**SearchContentTool:** Arguments: `pattern: String`, `path: String` (default: "."), `filePattern: String` (default: "*"). Line-by-line content search. Returns `file:line:content` format (limit 100 matches).

### Key: LanguageModelSession Handles the Agent Loop

The FoundationModels framework handles the agent loop natively:
- You register tools when creating the session
- The model decides when/how to call tools based on the prompt
- The framework orchestrates parallel and serial tool calls automatically
- You get back the final text response

This means we do NOT need to build our own agent loop — Apple's framework does it.

## Part 2: Apple Flow Integration (Later)

### Python Connector: `src/apple_flow/afm_connector.py`

Modeled on `codex_cli_connector.py`. Key differences:
- Default command: `apple-code`
- Passes `--cwd` and `--system` flags
- **Does NOT inject TOOLS_CONTEXT** (Swift binary has native tools)
- Aggressive context trimming: `context_window=1`, `max_prompt_chars=3000` (4096 token limit)
- Soul prompt truncated to ~500 chars

### Config Fields (`src/apple_flow/config.py`)

```python
afm_command: str = "apple-code"
afm_context_window: int = 1
afm_max_prompt_chars: int = 3000
```

### Daemon Wiring (`src/apple_flow/daemon.py`)

- Add `"afm"` to `known_connectors`
- Add `elif connector_type == "afm":` branch
- Soul prompt injection already works via `hasattr(self.connector, "set_soul_prompt")`

### .env.example

```
# AFM (Apple Foundation Models) — fully local on-device AI agent
# Uses Apple's ~3B model with native tool calling. No API keys needed.
# Requires: macOS 26+, Apple Silicon. Build: cd tools/apple-code && swift build -c release
# apple_flow_connector=afm
# apple_flow_afm_command=apple-code
# apple_flow_afm_context_window=1
# apple_flow_afm_max_prompt_chars=3000
```

### Tests: `tests/test_afm_connector.py`

Mirror `tests/test_cli_connector.py` (~16 tests):
- Protocol compliance, no-op methods, thread management
- Successful run (mock subprocess), --cwd and --system flags
- Timeout, command not found, error exit code, empty response
- Context window limiting, prompt truncation
- Verify TOOLS_CONTEXT is NOT injected
- Soul prompt truncation, streaming variant

## Known Limitations

- **4096 token context window**: Much smaller than cloud models. Complex multi-file tasks degraded.
- **~3B model capability**: Best for chat, idea, plan, simple file edits. May struggle with large refactors.
- **macOS 26+ only**: Won't compile on older macOS.
- **No TOOLS_CONTEXT**: AFM has native tools; doesn't need the AppleScript tools prompt.

## References

- [Apple FoundationModels Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [SwiftAgent SDK (community)](https://forums.swift.org/t/swiftagent-a-swift-native-agent-sdk-inspired-by-foundationmodels-and-using-its-tools/81634)
- [AI Agents with Apple Foundation Models](https://www.natashatherobot.com/p/ai-agents-apples-foundation-models-tool-calling)
- [afm CLI (Homebrew)](https://github.com/scouzi1966/maclocal-api)
- [afm-cli (Swift)](https://github.com/CreevekCZ/afm-cli)
