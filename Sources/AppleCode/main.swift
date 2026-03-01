import Foundation
import FoundationModels

func printUsage() {
    print("""
    apple-code - Local AI coding assistant powered by Apple Foundation Models

    Usage: apple-code [options] "prompt"

    Options:
      --system "..."          Custom system instructions
      --cwd /path/to/dir      Working directory for file/command tools
      --timeout N             Max seconds (default: 120)
      --no-apple-tools        Disable Apple app tools (Notes, Mail, etc.)
      -h, --help              Show this help

    Examples:
      apple-code "List files in the current directory"
      apple-code --cwd ~/projects/myapp "Read the README and summarize it"
      apple-code "Search my notes for meeting notes"
      echo "Explain this code" | apple-code
    """)
}

// ---------------------------------------------------------------------------
// Tool Router — selects only the tools relevant to a prompt.
// Apple app context takes priority over ambiguous words like "read"/"search".
// No keywords matched = no tools (just chat).
// ---------------------------------------------------------------------------

func routeTools(for prompt: String, includeAppleTools: Bool) -> [any Tool] {
    let p = prompt.lowercased()
    let words = Set(p.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })
    var selected: [any Tool] = []
    var hasAppleMatch = false

    // --- Apple app detection (checked FIRST — takes priority) ---
    if includeAppleTools {
        if words.contains("note") || words.contains("notes") {
            selected.append(NotesTool()); hasAppleMatch = true
        }
        if words.contains("mail") || words.contains("email") || words.contains("inbox") || words.contains("unread") {
            selected.append(MailTool()); hasAppleMatch = true
        }
        if words.contains("calendar") || words.contains("events") || words.contains("schedule") ||
           p.contains("meeting") || p.contains("appointment") {
            selected.append(CalendarTool()); hasAppleMatch = true
        }
        if words.contains("reminder") || words.contains("reminders") || words.contains("todo") || p.contains("to-do") {
            selected.append(RemindersTool()); hasAppleMatch = true
        }
        if words.contains("imessage") || words.contains("sms") || (words.contains("messages") && !words.contains("error")) ||
           (words.contains("message") && (p.contains("my message") || p.contains("text message") || p.contains("search"))) {
            selected.append(MessagesTool()); hasAppleMatch = true
        }
    }

    // If Apple tools matched, return just those — don't pollute with file tools
    if hasAppleMatch { return selected }

    // --- File/code tool detection ---
    let wantsFile = p.contains("file") || p.contains("readme") || p.contains("package.swift") ||
                    p.contains("read the") || p.contains("read this") || p.contains("show me the") ||
                    p.contains("open ") || p.contains("contents of") || p.contains("write to") ||
                    p.contains("create a file") || p.contains("save to") || p.contains("edit ")

    let wantsDir = p.contains("directory") || p.contains("folder") || p.contains("list files") ||
                   p.contains("what files") || p.contains("what's in") || p.contains("ls ") ||
                   p.contains("tree") || p.contains("show files")

    let wantsSearch = p.contains("grep") || p.contains("find all") || p.contains("search for") ||
                      p.contains("look for") || p.contains("locate") || p.contains("which files") ||
                      (p.contains("search") && (p.contains("file") || p.contains("code") || p.contains("project"))) ||
                      (p.contains("find") && (p.contains("file") || p.contains("code") || p.contains("function") || p.contains("class")))

    let wantsCommand = p.contains("run ") || p.contains("execute") || p.contains("shell") ||
                       p.contains("terminal") || p.contains("command") || words.contains("git") ||
                       words.contains("pip") || words.contains("npm") || words.contains("brew") ||
                       words.contains("make") || words.contains("curl") || words.contains("python") ||
                       words.contains("swift") || words.contains("cargo") || words.contains("docker")

    if wantsFile   { selected.append(ReadFileTool()); selected.append(WriteFileTool()) }
    if wantsDir    { selected.append(ListDirectoryTool()) }
    if wantsSearch { selected.append(SearchFilesTool()); selected.append(SearchContentTool()) }
    if wantsCommand { selected.append(RunCommandTool()) }

    // No matches = no tools. Model will just chat.
    return selected
}

// ---------------------------------------------------------------------------
// CLI Entry Point
// ---------------------------------------------------------------------------

let args = CommandLine.arguments

// Parse arguments
var promptParts: [String] = []
var systemInstructions: String?
var cwd: String?
var timeout: Int = 120
var noAppleTools = false

var i = 1
while i < args.count {
    switch args[i] {
    case "--system":
        i += 1
        if i < args.count { systemInstructions = args[i] }
    case "--cwd":
        i += 1
        if i < args.count { cwd = args[i] }
    case "--timeout":
        i += 1
        if i < args.count { timeout = Int(args[i]) ?? 120 }
    case "--no-apple-tools":
        noAppleTools = true
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        if !args[i].hasPrefix("-") {
            promptParts.append(args[i])
        }
    }
    i += 1
}
var prompt: String? = promptParts.isEmpty ? nil : promptParts.joined(separator: " ")

// Read from stdin if no positional prompt
if prompt == nil {
    if isatty(fileno(stdin)) == 0 {
        prompt = readLine(strippingNewline: false)
        if let p = prompt {
            var full = p
            while let line = readLine(strippingNewline: false) {
                full += line
            }
            prompt = full.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

guard let prompt = prompt, !prompt.isEmpty else {
    FileHandle.standardError.write(Data("Error: No prompt provided. Usage: apple-code \"your prompt\"\n".utf8))
    exit(1)
}

// Check availability
guard SystemLanguageModel.default.availability == .available else {
    FileHandle.standardError.write(Data("Error: Apple Foundation Models not available. Requires macOS 26+ on Apple Silicon.\n".utf8))
    exit(1)
}

// Set working directory
let workingDir: String
if let cwd = cwd {
    FileManager.default.changeCurrentDirectoryPath(cwd)
    workingDir = cwd
} else {
    workingDir = FileManager.default.currentDirectoryPath
}

// Route tools based on prompt
let tools = routeTools(for: prompt, includeAppleTools: !noAppleTools)

// Build instructions
let defaultPreamble = """
You are apple-code, a local AI coding assistant. Be concise.
Working directory: \(workingDir)
Only use tools when the user asks. For greetings or chat, just respond with text.
Never create, send, or modify anything unless explicitly asked.
"""
let instructions = systemInstructions.map { "\(defaultPreamble)\n\($0)" } ?? defaultPreamble

// Create session and respond
let session = LanguageModelSession(tools: tools, instructions: instructions)

do {
    let response = try await session.respond(to: prompt)
    print(response.content)
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
