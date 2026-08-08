# WWDC26 Model Upgrade Notes

`apple-code` is now structured around provider capabilities instead of only provider names.
The default remains local/offline Apple Foundation Models, while WWDC26-era lanes are
available as explicit opt-ins.

## Providers

- `apple`: on-device Apple Foundation Models through `SystemLanguageModel`.
- `apple-pcc`: Private Cloud Compute lane. The CLI/config/UI are wired, with a
  32K context budget and optional reasoning level, but runtime execution requires
  an SDK that exposes `PrivateCloudComputeLanguageModel`.
- `ollama`: practical larger local models today.
- `codex`: authenticated Codex CLI handoff for heavyweight coding turns.
- `coreai`: experimental placeholder for future `apple/coreai-models` `.aimodel`
  execution on macOS 27+ and Xcode 27+.
- `mlx`: experimental placeholder for a future `mlx-swift-lm` provider.

## Config

Supported model keys in `~/.apple-code/config` or project `.apple-code`:

```text
provider = apple-pcc
reasoning_level = moderate
model = qwen3.5:9b
base_url = http://127.0.0.1:11434
```

`reasoning_level` is accepted only for `provider = apple-pcc` and must be
`light`, `moderate`, or `deep`.

## Image Input

CLI syntax:

```bash
apple-code --provider apple --image ./screenshot.png "What is shown here?"
```

REPL syntax:

```text
/image ./screenshot.png describe the UI
[image: ./screenshot.png] describe the UI
```

The current active SDK does not expose a vision-capable Foundation Models prompt
surface, so image inputs are validated and then rejected unless the active model
capability reports vision support.

## Toolchain Prerequisite

`swift build` and `swift test` require a full Xcode toolchain that includes the
FoundationModels macro plugin. If the active developer directory is Command Line
Tools, builds fail with:

```text
FoundationModelsMacros.GenerableMacro could not be found
```

Fix once Xcode is installed:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift build
swift test
```

## Evaluation And Profiling

1. Run the fixture prompts in `evals/prompt-fixtures.jsonl` against each provider
   you want to compare.
2. Capture pass/fail, latency, selected tools, and final response quality.
3. For Apple providers, record a Foundation Models Instruments trace for:
   filesystem search/edit, Apple app lookup, long-context summarization, and web
   retrieval.
4. Use Apple Foundation Models Python SDK or `fm` when available for prompt
   iteration and batch scoring.

Recommended matrix:

- macOS 26 on-device Apple
- macOS 27 on-device Apple
- macOS 27 PCC available
- PCC unavailable or quota reached
- Ollama installed model
- Ollama missing model
- Codex CLI
