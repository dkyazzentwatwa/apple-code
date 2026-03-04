# apple-code

Swift 6.2+ CLI coding assistant. macOS 26+, no external dependencies.

## Key files
- `Sources/AppleCode/main.swift` — CLI args, `routeTools()`
- `Sources/AppleCode/REPLLoop.swift` — interactive REPL loop
- `Sources/AppleCode/ToolBridge.swift` — tool schemas + invoke switch
- `Sources/AppleCode/ModelClient.swift` — AFM + Ollama clients
- `Sources/AppleCode/Tools/` — one file per tool

## Adding a tool
1. Create `Sources/AppleCode/Tools/MyTool.swift` (conform to `Tool`)
2. Add schema case in `ToolBridge.schema(for:)`
3. Add invoke case in `ToolBridge.invoke()`
4. Add routing in `routeTools()` in `main.swift`

## Conventions
- Swift 6 strict concurrency — all shared state must be Sendable
- No third-party packages
- `swift build` must be clean (no warnings promoted to errors)
- 80% test coverage gate: `swift test`

## Build & install
```