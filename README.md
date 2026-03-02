# apple-code

> Local-first coding shell for Apple Foundation Models and Ollama.

`apple-code` is a Swift CLI assistant for coding workflows on macOS. It runs locally by default with Apple Foundation Models (AFM), and can switch to a local Ollama model (including Qwen variants) without any cloud API requirement.

## Highlights

- Local providers only: `apple` and `ollama`
- REPL settings menu (`/settings` or `Ctrl+P`) for fast provider/model/UI/theme switching
- Dynamic Ollama model picker from local install (`ollama list`)
- Tool-calling support with filesystem, shell, web, browser, and Apple app tools
- Session persistence, history, and quick switching

## Requirements

- macOS 26+ (Tahoe) on Apple Silicon
- Xcode 26+ command line tools
- Swift toolchain with Foundation Models support
- Ollama installed locally (for `--provider ollama`)

## Install

```bash
./scripts/install.sh
```

Use immediately:

```bash
export PATH="$HOME/.local/bin:$PATH"
apple-code
```

Upgrade later:

```bash
./scripts/install.sh
```

## Quick Start

```bash
# REPL
apple-code

# One-shot
apple-code "summarize this repo"

# Specific project dir
apple-code --cwd ~/projects/myapp
```

From source:

```bash
swift run apple-code
swift run apple-code "summarize this repo"
```

## Providers

### Apple Foundation Models (default)

```bash
apple-code --provider apple
```

### Ollama (local)

```bash
export OLLAMA_BASE_URL="http://127.0.0.1:11434"   # optional
export OLLAMA_MODEL="qwen3.5:4b"                    # optional

apple-code --provider ollama --model qwen3.5:4b
```

If a model is missing:

```bash
ollama pull qwen3.5:4b
```

In REPL, `/settings` can prompt and run pulls for you.

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

- `/settings` (provider/model/ui/theme/session menu)
- `/model`, `/m`
- `/ui [classic|framed]`
- `/theme <wow|minimal|classic|solar|ocean|forest>`
- `/session <id|next|prev>`

Utility:

- `/cd <path>`
- `/clear`, `/c`
- `/help`, `/h`

Hotkeys:

- `Ctrl+P` open settings
- `Esc (Ctrl+[)` previous session chip
- `Ctrl+]` next session chip

## CLI Options

```bash
apple-code --help
```

Common:

- `--provider <apple|ollama>`
- `--model <id>`
- `--base-url <url>`
- `--ui <classic|framed>`
- `--cwd /path/to/dir`
- `--timeout N`
- `--resume <session-id>`
- `--new`
- `--verbose`
- `--no-apple-tools`
- `--no-web-tools`
- `--no-browser-tools`

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
```

Validate Apple app integrations:

```bash
apple-code --check-apple-tools
```

Validate Ollama locally:

```bash
ollama list
curl http://127.0.0.1:11434/api/tags
```

## Development

```bash
swift build
swift build -c release
swift test
```
