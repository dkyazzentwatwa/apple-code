import Foundation
import FoundationModels

func printUsage() {
    print("""
    apple-code - Local AI coding assistant powered by Apple Foundation Models

    Usage: apple-code [options] ["prompt"]

    Options:
      --system "..."          Custom system instructions
      --cwd /path/to/dir     Working directory for file/command tools
      --timeout N            Max seconds (default: 120)
      --no-apple-tools       Disable Apple app tools (Notes, Mail, etc.)
      --check-apple-tools    Run Apple app diagnostics and exit
      --no-web-tools         Disable dedicated web search/fetch tools
      --no-browser-tools     Disable browser automation tools
      --run-web-fetch <url>  Run webFetch tool directly and exit
      --run-web-search "q"   Run webSearch tool directly and exit
      --run-web-limit N      Result count for --run-web-search (default: 5)
      --run-notes-action a   Run notes tool directly and exit
      --run-notes-query q    Query/title for --run-notes-action
      --run-notes-body b     Body text for --run-notes-action
      --verbose              Show full output (disable summary mode)
      -i, --interactive      Force interactive mode (default if no prompt)
      --resume <session-id>  Resume a session
      --new                  Start a new session (clears history)
      -h, --help             Show this help

    Interactive Commands:
      /quit, /q             Exit and save session
      /new, /n              Start new session
      /sessions, /s         List saved sessions
      /resume <id>          Resume a session
      /delete <id>          Delete a session
      /history [n]          Show recent transcript entries
      /show <id>            Show full transcript entry by ID
      /model, /m            Show model info
      /cd <path>            Change directory
      /clear, /c            Clear screen
      /theme <name>         Switch theme (wow, minimal, classic)
      /help, /h             Show help
      (:commands still supported for compatibility)

    Examples:
      # Interactive mode (REPL)
      apple-code
      apple-code --cwd ~/projects/myapp

      # One-off mode
      apple-code "List files in current directory"
      echo "Explain this code" | apple-code
      apple-code --resume <session-id>
    """)
}

func routeTools(
    for prompt: String,
    includeAppleTools: Bool,
    includeWebTools: Bool,
    includeBrowserTools: Bool
) -> [any Tool] {
    let p = prompt.lowercased()
    let words = Set(p.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })
    var selected: [any Tool] = []
    let hasNotesIntent = includeAppleTools && (
        words.contains("note")
        || words.contains("notes")
        || p.contains("apple notes")
        || p.contains("in my notes")
        || p.contains("in notes")
    )
    let hasExplicitWebIntent = p.contains("search web")
        || p.contains("search online")
        || p.contains("web search")
        || p.contains("online")
        || p.contains("internet")
        || p.contains("http://")
        || p.contains("https://")

    if includeAppleTools {
        if words.contains("note") || words.contains("notes") {
            selected.append(NotesTool())
        }
        if words.contains("mail") || words.contains("email") || words.contains("inbox") || words.contains("unread") {
            selected.append(MailTool())
        }
        if words.contains("calendar") || words.contains("events") || words.contains("schedule") ||
           p.contains("meeting") || p.contains("appointment") {
            selected.append(CalendarTool())
        }
        if words.contains("reminder") || words.contains("reminders") || words.contains("todo") || p.contains("to-do") {
            selected.append(RemindersTool())
        }
        if words.contains("imessage") || words.contains("sms") || (words.contains("messages") && !words.contains("error")) ||
           (words.contains("message") && (p.contains("my message") || p.contains("text message") || p.contains("search"))) {
            selected.append(MessagesTool())
        }
    }

    let wantsFile = !hasNotesIntent && (p.contains("file") || p.contains("readme") || p.contains("package.swift") ||
                    p.contains("read the") || p.contains("read this") || p.contains("show me the") ||
                    p.contains("open ") || p.contains("contents of") || p.contains("write to") ||
                    p.contains("create a file") || p.contains("save to") || p.contains("edit "))

    let wantsDir = !hasNotesIntent && (p.contains("directory") || p.contains("folder") || p.contains("list files") ||
                   p.contains("what files") || p.contains("what's in") || p.contains("ls ") ||
                   p.contains("tree") || p.contains("show files"))

    let wantsSearch = !hasNotesIntent && (p.contains("grep") || p.contains("find all") || p.contains("search for") ||
                      p.contains("look for") || p.contains("locate") || p.contains("which files") ||
                      (p.contains("search") && (
                        p.contains("file") || p.contains("files") || p.contains("project") ||
                        p.contains("repo") || p.contains("repository") || p.contains("codebase") ||
                        p.contains("search code for")
                      )) ||
                      (p.contains("find") && (p.contains("file") || p.contains("code") || p.contains("function") || p.contains("class"))))

    let wantsCommand = !hasNotesIntent && (p.contains("run ") || p.contains("execute") || p.contains("shell") ||
                       p.contains("terminal") || p.contains("command") || words.contains("git") ||
                       words.contains("pip") || words.contains("npm") || words.contains("brew") ||
                       words.contains("make") || words.contains("curl") || words.contains("python") ||
                       words.contains("swift") || words.contains("cargo") || words.contains("docker"))

    let wantsBrowser = includeBrowserTools && (
        p.contains("browser") || p.contains("website") || p.contains("web site") ||
        p.contains("open url") || p.contains("open this url") || p.contains("open link") ||
        p.contains("click") || p.contains("fill") || p.contains("form") ||
        p.contains("screenshot") || p.contains("snapshot") || p.contains("login") ||
        p.contains("agent-browser") || p.contains("agent browser")
    )

    let wantsPDF = p.contains("pdf") && (
        p.contains("create") || p.contains("make") || p.contains("generate") ||
        p.contains("export") || p.contains("save as") || p.contains("write")
    )

    let hasURLInPrompt = p.contains("http://")
        || p.contains("https://")
        || p.contains("littlehakr.substack.com")

    let wantsWebSearch = includeWebTools && (!hasNotesIntent || hasExplicitWebIntent) && (
        p.contains("search web") || p.contains("search online") || p.contains("web search") ||
        p.contains("latest") || p.contains("news about") || p.contains("look up online") ||
        (p.hasPrefix("search ") && !wantsSearch) || p.contains("search how to") || p.contains("look up ")
    )

    let wantsWebFetch = includeWebTools && (
        p.contains("fetch url") || p.contains("open this url") || p.contains("summarize this page") ||
        p.contains("extract from") || hasURLInPrompt
    )

    if wantsFile   { selected.append(ReadFileTool()); selected.append(WriteFileTool()) }
    if wantsDir    { selected.append(ListDirectoryTool()) }
    if wantsSearch { selected.append(SearchFilesTool()); selected.append(SearchContentTool()) }
    if wantsCommand { selected.append(RunCommandTool()) }
    if wantsPDF { selected.append(CreatePDFTool()) }
    if wantsWebSearch { selected.append(WebSearchTool()) }
    if wantsWebFetch { selected.append(WebFetchTool()) }
    if wantsBrowser { selected.append(AgentBrowserTool()) }

    var deduped: [any Tool] = []
    var seen = Set<String>()
    for tool in selected {
        if seen.insert(tool.name).inserted {
            deduped.append(tool)
        }
    }

    return deduped
}

let args = CommandLine.arguments

var promptParts: [String] = []
var systemInstructions: String?
var cwd: String?
var timeout: Int = 120
var noAppleTools = false
var checkAppleTools = false
var noWebTools = false
var noBrowserTools = false
var runWebFetchURL: String?
var runWebSearchQuery: String?
var runWebSearchLimit = 5
var runNotesAction: String?
var runNotesQuery: String?
var runNotesBody: String?
var verbose = false
var forceInteractive = false
var resumeSessionId: UUID?
var startNewSession = false

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
    case "--check-apple-tools":
        checkAppleTools = true
    case "--no-web-tools":
        noWebTools = true
    case "--no-browser-tools":
        noBrowserTools = true
    case "--run-web-fetch":
        i += 1
        if i < args.count { runWebFetchURL = args[i] }
    case "--run-web-search":
        i += 1
        if i < args.count { runWebSearchQuery = args[i] }
    case "--run-web-limit":
        i += 1
        if i < args.count { runWebSearchLimit = Int(args[i]) ?? 5 }
    case "--run-notes-action":
        i += 1
        if i < args.count { runNotesAction = args[i] }
    case "--run-notes-query":
        i += 1
        if i < args.count { runNotesQuery = args[i] }
    case "--run-notes-body":
        i += 1
        if i < args.count { runNotesBody = args[i] }
    case "--verbose":
        verbose = true
    case "-i", "--interactive":
        forceInteractive = true
    case "--resume":
        i += 1
        if i < args.count { resumeSessionId = UUID(uuidString: args[i]) }
    case "--new":
        startNewSession = true
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
var promptArg: String? = promptParts.isEmpty ? nil : promptParts.joined(separator: " ")

if promptArg == nil && isatty(fileno(stdin)) == 0 {
    var stdinInput = ""
    while let line = readLine(strippingNewline: false) {
        stdinInput += line
    }
    if !stdinInput.isEmpty {
        promptArg = stdinInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

if let fetchURL = runWebFetchURL {
    let result = try await WebFetchTool().call(arguments: .init(url: fetchURL, maxChars: 12_000))
    print(result)
    exit(0)
}

if let searchQuery = runWebSearchQuery {
    let result = try await WebSearchTool().call(arguments: .init(query: searchQuery, limit: runWebSearchLimit))
    print(result)
    exit(0)
}

if let notesAction = runNotesAction {
    let result = try await NotesTool().call(arguments: .init(action: notesAction, query: runNotesQuery, body: runNotesBody))
    print(result)
    exit(0)
}

if checkAppleTools {
    let result = await runAppleToolDiagnostics()
    print(result)
    exit(0)
}

guard SystemLanguageModel.default.availability == .available else {
    FileHandle.standardError.write(Data("Error: Apple Foundation Models not available. Requires macOS 26+ on Apple Silicon.\n".utf8))
    exit(1)
}

let workingDir: String
if let cwd = cwd {
    FileManager.default.changeCurrentDirectoryPath(cwd)
    workingDir = cwd
} else {
    workingDir = FileManager.default.currentDirectoryPath
}

let shouldBeInteractive = forceInteractive || promptArg == nil || promptArg?.isEmpty == true

if shouldBeInteractive {
    var session: Session

    if let resumeId = resumeSessionId {
        do {
            session = try SessionManager.shared.loadSession(id: resumeId)
            let idStr = String(resumeId.uuidString.prefix(8))
            printSuccess("Resumed session \(idStr)")
        } catch {
            printError("Could not load session: \(error.localizedDescription)")
            exit(1)
        }
    } else if startNewSession {
        session = SessionManager.shared.createSession(workingDir: workingDir)
    } else {
        session = SessionManager.shared.createSession(workingDir: workingDir)
    }

    await runInteractiveREPL(
        session: &session,
        systemInstructions: systemInstructions,
        timeout: timeout,
        includeAppleTools: !noAppleTools,
        includeWebTools: !noWebTools,
        includeBrowserTools: !noBrowserTools,
        verbose: verbose
    )
}

guard let prompt = promptArg, !prompt.isEmpty else {
    FileHandle.standardError.write(Data("Error: No prompt provided. Use --interactive for REPL mode.\n".utf8))
    exit(1)
}

let tools = routeTools(
    for: prompt,
    includeAppleTools: !noAppleTools,
    includeWebTools: !noWebTools,
    includeBrowserTools: !noBrowserTools
)

var defaultPreamble = """
You are apple-code, a local AI coding assistant. Be concise.
Working directory: \(workingDir)
For greetings or chat, respond naturally with plain text.
For harmless requests (jokes, explanations, brainstorming, code snippets, styling help), answer directly and do not refuse.
Do not claim inability unless the request is actually disallowed or impossible.
Use tools only when they materially help with what the user asked.
Never create, send, or modify external resources unless explicitly asked.
If a request is unclear, ask one concise clarifying question instead of refusing.
"""
if !noWebTools {
    defaultPreamble += """

For web retrieval, prefer webSearch for discovery and webFetch for direct page content.
Do not claim you cannot access websites when web tools are available; use webFetch/webSearch first.
When using web sources, include URLs in your final answer.
"""
}
if !noAppleTools {
    defaultPreamble += """

For Apple apps (Reminders, Notes, Calendar, Mail, Messages), use available Apple tools instead of saying you cannot access them.
If requested Apple data is available via tools, retrieve it directly.
For Apple Notes requests, prefer notes tool actions (list_folders, list, search, get_content, create, append) before web/file tools.
"""
}
if !noBrowserTools {
    defaultPreamble += """

For browser tasks, use the agentBrowser tool.
Use this sequence for web interaction: open -> snapshot -> interact -> snapshot.
"""
}
defaultPreamble += """

For shell/terminal requests, use the runCommand tool instead of saying you cannot execute commands.
"""
let instructions = systemInstructions.map { "\(defaultPreamble)\n\($0)" } ?? defaultPreamble

let llmSession = LanguageModelSession(tools: tools, instructions: instructions)

do {
    var content = try await withResponseTimeout(seconds: timeout) {
        let response = try await llmSession.respond(to: prompt)
        return response.content
    }

    if !noAppleTools,
       let recovered = await resolveAppleRefusalFallback(
           userPrompt: prompt,
           modelReply: content
       ) {
        content = recovered
    }

    if !noAppleTools,
       let recovered = await resolveNotesComposeFallback(
           userPrompt: prompt,
           modelReply: content
       ) {
        content = recovered
    }

    if !noWebTools,
       let recovered = await resolveWebRefusalFallback(
           userPrompt: prompt,
           modelReply: content,
           instructions: instructions,
           timeoutSeconds: timeout
       ) {
        content = recovered
    }

    if let recovered = await resolveCommandRefusalFallback(
        userPrompt: prompt,
        modelReply: content,
        timeoutSeconds: timeout
    ) {
        content = recovered
    }

    printAssistantMessage(content, verbose: verbose)
} catch {
    let err = error.localizedDescription
    if !noAppleTools,
       isAppleIntentPrompt(prompt),
       (err.contains("Failed to deserialize a Generable type")
        || err.contains("The operation couldn’t be completed")) {
        if let recovered = await resolveAppleIntentDirect(userPrompt: prompt) {
            printAssistantMessage(recovered, verbose: verbose)
            exit(0)
        }
    }
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
