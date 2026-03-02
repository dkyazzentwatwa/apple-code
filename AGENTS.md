# AGENTS.md - Apple Code Agent Guidelines

This file provides guidelines for agentic coding agents working on the `apple-code` project.

## Project Overview

`apple-code` is a Swift CLI tool that uses Apple's FoundationModels framework to provide a local AI coding assistant with file, shell, and Apple app integration tools (Notes, Mail, Calendar, Reminders, Messages). It runs on macOS 26+ with Apple Silicon.

## Build Commands

### Build and Run

```bash
# Build the project
swift build

# Build release version
swift build -c release

# Run the CLI
swift run apple-code "your prompt"

# Or build then run the binary directly
swift build -c release
./.build/release/apple-code "your prompt"
```

### CLI Options

```
apple-code [options] ["prompt"]
  --system "..."       Custom system instructions
  --cwd /path/to/dir  Working directory for file/command tools
  --timeout N          Max seconds (default: 120)
  --no-apple-tools    Disable Apple app tools
  -i, --interactive    Force interactive REPL mode
  --resume <id>        Resume a saved session
  --new               Start a new session
  -h, --help          Show help

# Interactive Commands (in REPL mode):
  :quit, :q           Exit and save session
  :new, :n            Start new session
  :sessions, :s       List saved sessions
  :resume <id>        Resume a session
  :delete <id>        Delete a session
  :model, :m          Show model info
  :cd <path>          Change directory
  :clear, :c          Clear screen
  :help, :h           Show help
```

### Testing

- No test suite currently exists for this project
- To add tests, create a `Tests/` directory with XCTest or Swift Testing
- Run tests with: `swift test`

### Linting

- No linting configuration exists
- Swift code follows standard Swift conventions (Swift.org style guide)
- Optional: Install [SwiftLint](https://github.com/realm/SwiftLint) for style enforcement

---

## Code Style Guidelines

### General Principles

- Use Swift standard library and Apple's FoundationModels framework
- Prefer value types (`struct`) over reference types (`class`) unless reference semantics are needed
- Keep functions small and focused on a single responsibility
- Use explicit types for function parameters and return values

### File Organization

- One public type per file (use private helpers in same file if closely related)
- File name matches type name: `ReadFileTool.swift` contains `struct ReadFileTool`
- Group related tools in `Sources/AppleCode/Tools/`
- Shared utilities (e.g., `AppleScriptRunner.swift`) in `Sources/AppleCode/`

### Imports

```swift
import Foundation
import FoundationModels  // Required for Tool protocol and LanguageModelSession
```

- Only import what's needed
- Foundation first, then third-party frameworks

### Naming Conventions

- **Types**: PascalCase (`ReadFileTool`, `LanguageModelSession`)
- **Functions**: camelCase (`routeTools`, `printUsage`)
- **Properties/Variables**: camelCase (`prompt`, `workingDir`, `timeout`)
- **Constants**: camelCase, prefer local constants over global
- **Enums**: PascalCase with capitalized cases (`case list_folders` for AppleScript interoperability)

### Structs for Tools

All tools conform to the `Tool` protocol from FoundationModels:

```swift
struct ToolName: Tool {
    let name = "toolName"
    let description = "What the tool does"

    @Generable
    struct Arguments {
        @Guide(description: "Parameter description")
        let paramName: Type
    }

    func call(arguments: Arguments) async throws -> String {
        // Implementation
    }
}
```

### Error Handling

- Use `try`/`try?` for throwing functions
- Return error messages as strings from tools (not thrown exceptions) for better LLM readability
- Log critical errors to stderr before exit:

```swift
FileHandle.standardError.write(Data("Error: message\n".utf8))
exit(1)
```

### Tool Implementation Patterns

1. **Return strings, not structured data**: Tools return `String` output that the LLM can interpret
2. **Truncate large outputs**: Files >50KB, command output >100KB should be truncated
3. **Safety first**: `RunCommandTool` has a blocklist for dangerous commands
4. **Timeout handling**: Use `DispatchWorkItem` with timeout for long-running operations

### Working Directory

- Use `FileManager.default.changeCurrentDirectoryPath(_:)` when `--cwd` is provided
- Tools operate relative to the working directory
- Include working directory in system preamble for LLM context

### AppleScript Integration

- Use `AppleScriptRunner.run(script)` helper for Apple app integration
- Format results consistently using `AppleScriptRunner.formatRecords()`
- Handle `nil` returns gracefully (app not running, permission denied, etc.)

### Preamble/System Instructions

Default preamble structure:

```
You are apple-code, a local AI coding assistant. Be concise.
Working directory: {cwd}
Only use tools when the user asks. For greetings or chat, just respond with text.
Never create, send, or modify anything unless explicitly asked.
```

Append custom `--system` instructions after the default preamble.

---

## Key Files

| File | Purpose |
|------|---------|
| `Sources/AppleCode/main.swift` | CLI entry point, argument parsing, tool routing |
| `Sources/AppleCode/REPLLoop.swift` | Interactive REPL loop with session management |
| `Sources/AppleCode/Session.swift` | Session model and persistence |
| `Sources/AppleCode/CLICommands.swift` | Interactive command handlers (:help, :quit, etc.) |
| `Sources/AppleCode/TUIUtils.swift` | Terminal UI utilities (colors, formatting) |
| `Sources/AppleCode/AppleScriptRunner.swift` | AppleScript execution helper |
| `Sources/AppleCode/Tools/ReadFileTool.swift` | File reading (50KB limit) |
| `Sources/AppleCode/Tools/WriteFileTool.swift` | File writing |
| `Sources/AppleCode/Tools/RunCommandTool.swift` | Shell command execution |
| `Sources/AppleCode/Tools/ListDirectoryTool.swift` | Directory listing |
| `Sources/AppleCode/Tools/SearchFilesTool.swift` | Glob-based file search |
| `Sources/AppleCode/Tools/SearchContentTool.swift` | Grep-like content search |
| `Sources/AppleCode/Tools/NotesTool.swift` | Apple Notes integration |
| `Sources/AppleCode/Tools/MailTool.swift` | Apple Mail integration |
| `Sources/AppleCode/Tools/CalendarTool.swift` | Apple Calendar integration |
| `Sources/AppleCode/Tools/RemindersTool.swift` | Apple Reminders integration |
| `Sources/AppleCode/Tools/MessagesTool.swift` | Apple Messages (iMessage) integration |

---

## Known Limitations

- Requires macOS 26+ on Apple Silicon
- ~4096 token context window (much smaller than cloud models)
- Best for simple tasks; complex multi-file refactoring may degrade
- No Apple app tools on non-Apple Silicon Macs

---

## Adding New Tools

1. Create `Sources/AppleCode/Tools/NewToolName.swift`
2. Define struct conforming to `Tool` protocol
3. Implement `call(arguments:)` async function returning `String`
4. Add tool detection keywords in `main.swift:routeTools()` function
5. Test with: `swift run apple-code "your prompt with tool trigger keywords"`
