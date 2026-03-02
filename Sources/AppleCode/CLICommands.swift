import Foundation

enum CLICommand {
    case quit
    case newSession
    case listSessions
    case resumeSession(UUID)
    case deleteSession(UUID)
    case showHelp
    case showModel
    case changeDirectory(String)
    case clear
    case setTheme(String?)
    case none
}

func parseCommand(_ input: String) -> CLICommand {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let prefix = trimmed.first, prefix == ":" || prefix == "/" else { return .none }

    let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
    let cmd = parts.first?.lowercased() ?? ""
    let arg = parts.count > 1 ? parts[1] : ""

    switch cmd {
    case "q", "quit", "exit":
        return .quit
    case "n", "new", "new-session":
        return .newSession
    case "s", "sessions", "list-sessions":
        return .listSessions
    case "r", "resume", "load":
        if let uuid = UUID(uuidString: arg) {
            return .resumeSession(uuid)
        }
        return .none
    case "d", "delete", "rm":
        if let uuid = UUID(uuidString: arg) {
            return .deleteSession(uuid)
        }
        return .none
    case "h", "help", "?":
        return .showHelp
    case "m", "model":
        return .showModel
    case "cd":
        if !arg.isEmpty {
            return .changeDirectory(arg)
        }
        return .none
    case "c", "clear":
        return .clear
    case "theme":
        return .setTheme(arg.isEmpty ? nil : arg)
    default:
        return .none
    }
}

func printHelp() {
    print("""
    \(TUI.bold)Available Commands:\(TUI.reset)

    \(TUI.promptColor)/new\(TUI.reset) (or /n)     Start a new session
    \(TUI.promptColor)/sessions\(TUI.reset) (or /s)  List all saved sessions
    \(TUI.promptColor)/resume <id>\(TUI.reset)      Resume a session by ID
    \(TUI.promptColor)/delete <id>\(TUI.reset)      Delete a session
    \(TUI.promptColor)/model\(TUI.reset) (or /m)     Show current model info
    \(TUI.promptColor)/cd <path>\(TUI.reset)        Change working directory
    \(TUI.promptColor)/clear\(TUI.reset) (or /c)    Clear the screen
    \(TUI.promptColor)/theme <name>\(TUI.reset)     Switch theme (wow, minimal, classic)
    \(TUI.promptColor)/help\(TUI.reset) (or /h)    Show this help
    \(TUI.promptColor)/quit\(TUI.reset) (or /q)     Exit apple-code

    \(TUI.mutedColor)Compatibility: :commands still work.\(TUI.reset)

    \(TUI.mutedColor)Keys: Enter submit, Ctrl+J newline, arrows navigate history/edit.\(TUI.reset)
    \(TUI.mutedColor)Tip: Just type a message to chat. The AI will use tools when needed.\(TUI.reset)
    """)
}

func handleSessionList() async {
    let sessions = await SessionManager.shared.listSessions()

    if sessions.isEmpty {
        printMuted("No saved sessions.")
        return
    }

    print("\(TUI.bold)Saved Sessions:\(TUI.reset)\n")
    for session in sessions {
        let idStr = String(session.id.uuidString.prefix(8))
        print("\(TUI.promptColor)\(idStr)\(TUI.reset)  \(session.formattedDate)  \(session.messageCount) messages")
        print("   \(TUI.mutedColor)\(session.preview)\(TUI.reset)")
        print("   \(TUI.mutedColor)wd: \(session.workingDir)\(TUI.reset)")
        print()
    }
}

func handleResumeSession(id: UUID) async -> Session? {
    do {
        let session = try await SessionManager.shared.loadSession(id: id)
        let idStr = String(id.uuidString.prefix(8))
        printSuccess("Resumed session \(idStr)")
        printMuted("Working directory: \(session.workingDir)")
        printMuted("Messages: \(session.messages.count)")
        print()
        return session
    } catch {
        printError("Could not load session: \(error.localizedDescription)")
        return nil
    }
}

func handleDeleteSession(id: UUID) async {
    do {
        try await SessionManager.shared.deleteSession(id: id)
        let idStr = String(id.uuidString.prefix(8))
        printSuccess("Deleted session \(idStr)")
    } catch {
        printError("Could not delete session: \(error.localizedDescription)")
    }
}
