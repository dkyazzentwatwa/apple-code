# apple-code

<p align="center">
  <img src="assets/banner.svg" alt="apple-code banner" width="100%" />
</p>

<p align="center">
  Local-first coding shell for Apple Foundation Models and Ollama.
</p>

<p align="center">
  <a href="https://github.com/dkyazzentwatwa/apple-code/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/dkyazzentwatwa/apple-code/actions/workflows/ci.yml/badge.svg?branch=main" /></a>
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" />
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" />
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg" /></a>
</p>

<p align="center">
  <img src="assets/apple-code1.png" alt="apple-code screenshot 1" width="48%" />
  <img src="assets/apple-code2.png" alt="apple-code screenshot 2" width="48%" />
</p>

`apple-code` is a Swift CLI assistant for local coding workflows on macOS. It runs on-device with Apple Foundation Models by default, and can switch to local Ollama models (including Qwen variants) with no cloud API dependency.

## Highlights

- Local providers only: `apple` and `ollama`
- Fast settings menu in REPL: `/settings` or `Ctrl+P`
- Dynamic local Ollama model picker using `ollama list`
- Tool-calling support for filesystem, shell, web, browser, PDF, and Apple apps
- Session persistence, transcript history, and quick session switching
- Two UI modes (`classic`, `framed`) and multiple built-in themes

## Requirements

- macOS 26+ (Tahoe) on Apple Silicon
- Xcode 26+ command line tools
- Swift toolchain with FoundationModels support
- Ollama installed locally for `--provider ollama`

## Install

### Recommended

```bash
./scripts/install.sh
```

Then:

```bash
export PATH="$HOME/.local/bin:$PATH"
apple-code
```

Installer options:

```bash
./scripts/install.sh --help
```

### Run from Source

```bash
swift run apple-code
swift run apple-code "summarize this repo"
```

## Quick Start

```bash
# REPL
apple-code

# One-shot
apple-code "summarize this repo"

# Specific project directory
apple-code --cwd ~/projects/myapp
```

## Providers

### Apple Foundation Models (default)

```bash
apple-code --provider apple
```

### Ollama (local)

```bash
export OLLAMA_BASE_URL="http://127.0.0.1:11434"
export OLLAMA_MODEL="qwen3.5:4b"

apple-code --provider ollama --model qwen3.5:4b
```

If a model is missing:

```bash
ollama pull qwen3.5:4b
```

In REPL, `/settings` can prompt and run pulls for you.

## CLI Options

```text
apple-code [options] ["prompt"]

--system "..."          Custom system instructions
--cwd /path/to/dir      Working directory for file/command tools
--provider <name>       Model provider: apple | ollama
--model <id>            Model ID (ollama)
--base-url <url>        Base URL for ollama (default: http://127.0.0.1:11434)
--ui <mode>             UI mode: classic | framed
--timeout N             Max seconds (default: 120)
--no-apple-tools        Disable Apple app tools (Notes, Mail, etc.)
--check-apple-tools     Run Apple app diagnostics and exit
--no-web-tools          Disable dedicated web search/fetch tools
--no-browser-tools      Disable browser automation tools
--run-web-fetch <url>   Run webFetch tool directly and exit
--run-web-search "q"    Run webSearch tool directly and exit
--run-web-limit N       Result count for --run-web-search (default: 5)
--run-notes-action a    Run notes tool directly and exit
--run-notes-query q     Query/title for --run-notes-action
--run-notes-body b      Body text for --run-notes-action
--security-profile p    Security profile: secure | balanced | compatibility
--allow-path /path      Additional allowed filesystem root (repeatable)
--allow-host host       Allowed web host/domain (repeatable)
--allow-private-network Allow localhost/private network URLs
--dangerous-without-confirm Allow dangerous mutating actions without extra gate
--allow-fallback-execution  Allow automatic refusal fallback tool execution
--verbose               Show full output (disable summary mode)
-i, --interactive       Force interactive mode
--resume <session-id>   Resume a session
--new                   Start a new session
-h, --help              Show help
```

## REPL Commands

Core:

- `/new`, `/n`
- `/sessions`, `/s`
- `/resume <id>`
- `/delete <id>`
- `/history [n]`
- `/show <id>`
- `/quit`, `/q`

Settings and model control:

- `/settings`
- `/model`, `/m`
- `/ui [classic|framed]`
- `/theme <wow|minimal|classic|solar|ocean|forest>`
- `/session <id|next|prev>`

Utility:

- `/cd <path>`
- `/clear`, `/c`
- `/help`, `/h`

Compatibility:

- `:commands` are still supported

Hotkeys:

- `Ctrl+P` open settings
- `Esc (Ctrl+[)` previous session chip
- `Ctrl+]` next session chip
- Arrow keys for inline editing/history
- `Ctrl+J` insert newline in input

## Built-in Tools

| Category | Tools |
|---|---|
| Filesystem | `readFile`, `writeFile`, `listDirectory`, `searchFiles`, `searchContent`, `createPDF` |
| Shell | `runCommand` |
| Apple apps | `notes`, `mail`, `calendar`, `reminders`, `messages` |
| Web | `webSearch`, `webFetch` |
| Browser automation | `agentBrowser` |

## Troubleshooting

Check installed binary:

```bash
which apple-code
apple-code --help
```

Validate Apple app integrations:

```bash
apple-code --check-apple-tools
```

Validate Ollama:

```bash
ollama list
curl http://127.0.0.1:11434/api/tags
```

If `--provider ollama` fails:

- Confirm Ollama is running locally
- Verify model exists with `ollama list`
- Set `OLLAMA_BASE_URL` if using a non-default host/port

## Development

```bash
swift build
swift build -c release
swift test
./scripts/coverage.sh
```

`./scripts/coverage.sh` enforces an 80% line-coverage gate on the unit-testable core modules and also prints full-project coverage for visibility.

## License

Released under the MIT License. See [LICENSE](LICENSE).
