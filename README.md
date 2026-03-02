# apple-code

Local AI coding assistant CLI built with Apple's Foundation Models framework.

`apple-code` runs on-device, supports file/shell tools, Apple app integrations, web retrieval, and browser automation.

## What Is New

Recent updates added a full web retrieval stack and stronger failure recovery:

- `webSearch` tool with backend fallback chain:
  1. Site-specific crawl (for `site:domain` style queries)
  2. Brave Search API (when `BRAVE_SEARCH_API_KEY` is set)
  3. Brave search snapshot parser via `r.jina.ai`
  4. Bing HTML fallback
- `webFetch` tool for direct URL extraction with readable text output
- Automatic refusal recovery when model answers with "I cannot access the internet"
- Better URL/news handling in prompt routing (`search ...`, `latest ...`, URL prompts)
- Dedicated CNN headline extraction for cleaner "latest news" results
- Substack archive fallback when homepage content is JS-gated
- `agentBrowser` tool integration for real browser automation via `agent-browser`
- Response timeout wrapper for model calls to prevent hanging

## Requirements

- macOS 26+ (Tahoe) on Apple Silicon
- Xcode 26+ command line tools
- Swift toolchain with Foundation Models support

## Install (Recommended)

From the repo root:

```bash
./scripts/install.sh
```

This builds a release binary and installs it to `~/.local/bin/apple-code` by default.

Quick start after install:

```bash
export PATH="$HOME/.local/bin:$PATH"
apple-code
```

To persist `PATH` across shell restarts:

```bash
# zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

Then open a new shell (or `source ~/.zshrc` / `source ~/.bashrc`).

Installer options:

```bash
./scripts/install.sh --help
./scripts/install.sh --target ~/bin
./scripts/install.sh --yes --no-path-edit
./scripts/install.sh --force
```

## Build

```bash
swift build
swift build -c release
```

## Run

### Installed binary (recommended)

```bash
apple-code
apple-code "summarize this repo"
apple-code --cwd ~/projects/myapp
```

### One-off prompt

```bash
swift run apple-code "summarize this repo"
```

### Interactive REPL

```bash
swift run apple-code
```

### Use a specific working directory

```bash
swift run apple-code --cwd ~/projects/myapp
```

## CLI Options

```text
apple-code [options] ["prompt"]

--system "..."          Custom system instructions
--cwd /path/to/dir      Working directory for file/command tools
--timeout N             Max seconds (default: 120)
--no-apple-tools        Disable Apple app tools
--check-apple-tools     Run Apple app diagnostics and exit
--no-web-tools          Disable webSearch/webFetch tools
--no-browser-tools      Disable agentBrowser tool
--run-web-fetch <url>   Run webFetch directly and exit
--run-web-search "q"    Run webSearch directly and exit
--run-web-limit N       Result count for --run-web-search (default: 5)
--run-notes-action a    Run notes tool directly and exit
--run-notes-query q     Query/title for --run-notes-action
--run-notes-body b      Body text for --run-notes-action
-i, --interactive       Force interactive mode
--resume <session-id>   Resume a saved session
--new                   Start a new session
-h, --help              Show help
```

## REPL Commands

```text
/quit, /q
/new, /n
/sessions, /s
/resume <id>
/delete <id>
/model, /m
/cd <path>
/clear, /c
/theme <name>
/help, /h
(:commands still supported for compatibility)
```

Advanced composer keybindings:

- `Enter` submit
- `Ctrl+J` newline
- Arrow keys/Home/End move cursor

## Tooling Overview

| Category | Tools |
|---|---|
| Filesystem | `readFile`, `writeFile`, `listDirectory`, `searchFiles`, `searchContent`, `createPDF` |
| Shell | `runCommand` |
| Apple apps | `notes`, `mail`, `calendar`, `reminders`, `messages` |
| Web | `webSearch`, `webFetch` |
| Browser automation | `agentBrowser` |

## Web Search Configuration

### Optional: Brave Search API key

If set, `webSearch` will prefer official Brave API results.

```bash
export BRAVE_SEARCH_API_KEY="your_key_here"
```

You can also run one-shot:

```bash
BRAVE_SEARCH_API_KEY="your_key_here" swift run apple-code --run-web-search "how to install claude code"
```

### Direct tool debugging

Use these when validating behavior independently of model tool-calling:

```bash
swift run apple-code --run-web-search "how to set up vapi ai webhook token" --run-web-limit 5
swift run apple-code --run-web-fetch https://cnn.com
```

Direct Notes debugging:

```bash
swift run apple-code --run-notes-action list_folders
swift run apple-code --run-notes-action search --run-notes-query "App Intents"
swift run apple-code --run-notes-action get_content --run-notes-query "debug-plan"
swift run apple-code --run-notes-action create --run-notes-query "apple-code-test" --run-notes-body "hello"
```

PDF generation:

```bash
swift run apple-code "create a pdf at /tmp/example.pdf titled Project Brief with content This is a one-page summary."
```

## Web Refusal Recovery

When the model responds with internet-access refusals or thin web answers, `apple-code` now attempts recovery by:

1. Detecting likely refusal text
2. Running `webFetch` (for URL prompts) or `webSearch` (for non-URL prompts)
3. Optionally fetching top search result content
4. Re-answering with retrieved context
5. Falling back to source/result lists if generation still fails

This is why prompts like `latest new from https://cnn.com` now return headlines instead of "I cannot access the internet.".

## Apple Tool Diagnostics

You can now run a built-in Apple integration check:

```bash
swift run apple-code --check-apple-tools
```

It reports per-app status for:

- Reminders
- Notes
- Calendar
- Mail
- Messages

Statuses are:

- `OK` (tool reachable)
- `BLOCKED` (usually Automation or Full Disk Access permission)
- `ERROR` (other runtime/tool error)

## Browser Automation (`agent-browser`)

If you have `agent-browser` installed, `agentBrowser` can run actions like:

- `open`
- `snapshot`
- `click`
- `fill`
- `type`
- `press`
- `wait`
- `get_text`
- `get_url`
- `get_title`
- `screenshot`
- `close`

Install and verify separately in your shell, then use normal prompts that imply browser interaction.

## Session and Binary Notes

- `/new` resets conversation history, but does not reload code.
- To load code changes, exit REPL and restart process.
- Running `apple-code` may use an older global binary if multiple installs exist in `PATH`.
- Running `swift run apple-code ...` from this repo always uses latest local source.
- Upgrade an installed user-local binary by rerunning:

```bash
./scripts/install.sh
```

Troubleshooting: unsigned/dev builds may be blocked when copied to `/usr/local/bin` by macOS security policy.
Prefer `~/.local/bin` (installer default) for local source builds.

## Safety and Limits

- `runCommand` blocks a small set of dangerous command patterns.
- Tool outputs are truncated to keep responses manageable.
- Some websites use anti-bot protections; search/fetch quality depends on upstream responses.
- Foundation Models context window is limited compared to large cloud models.

## Project Structure

```text
Sources/AppleCode/main.swift                 # CLI entrypoint and tool routing
Sources/AppleCode/REPLLoop.swift             # Interactive loop
Sources/AppleCode/Session.swift              # Session persistence
Sources/AppleCode/CLICommands.swift          # REPL command handlers
Sources/AppleCode/TUIUtils.swift             # Terminal formatting and banner
Sources/AppleCode/WebFallback.swift          # Refusal/thin-answer recovery
Sources/AppleCode/WebTextUtils.swift         # HTML/text cleanup
Sources/AppleCode/ResponseTimeout.swift      # Response timeout helper
Sources/AppleCode/Tools/*.swift              # Tool implementations
```

## Development Notes

- No formal test suite is present yet.
- You can add tests under `Tests/` and run with:

```bash
swift test
```

## License

Add your preferred license here.
