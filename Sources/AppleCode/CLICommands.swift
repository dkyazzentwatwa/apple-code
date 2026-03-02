import Foundation
import Darwin

enum CLICommand {
    case quit
    case newSession
    case listSessions
    case resumeSession(UUID)
    case deleteSession(UUID)
    case showHistory(Int?)
    case showMessage(Int)
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
    case "hist", "history":
        if arg.isEmpty {
            return .showHistory(nil)
        }
        if let count = Int(arg), count > 0 {
            return .showHistory(count)
        }
        return .none
    case "show":
        if let id = Int(arg), id > 0 {
            return .showMessage(id)
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
    \(TUI.promptColor)/history [n]\(TUI.reset)      Show recent transcript entries
    \(TUI.promptColor)/show <id>\(TUI.reset)        Show full entry by transcript ID
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
    let width = currentTerminalWidth()
    let idWidth = 10
    let dateWidth = 12
    let countWidth = 10
    let previewWidth = max(20, width - (idWidth + dateWidth + countWidth + 8))

    let header = "\(pad("ID", to: idWidth))  \(pad("Updated", to: dateWidth))  \(pad("Messages", to: countWidth))  Preview"
    print("\(TUI.dim)\(header)\(TUI.reset)")
    print("\(TUI.dim)\(String(repeating: "─", count: max(40, min(width, header.count + previewWidth))))\(TUI.reset)")

    for session in sessions {
        let idStr = String(session.id.uuidString.prefix(8))
        let updated = session.formattedDate
        let msgCount = "\(session.messageCount)"
        let preview = truncate(session.preview, to: previewWidth)
        let wd = truncate(session.workingDir, to: previewWidth)
        print("\(TUI.promptColor)\(pad(idStr, to: idWidth))\(TUI.reset)  \(pad(updated, to: dateWidth))  \(pad(msgCount, to: countWidth))  \(preview)")
        print("   \(TUI.mutedColor)wd: \(wd)\(TUI.reset)")
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

private func currentTerminalWidth() -> Int {
    var w = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
        return max(60, Int(w.ws_col))
    }
    return 120
}

private func pad(_ text: String, to width: Int) -> String {
    if text.count >= width { return String(text.prefix(width)) }
    return text + String(repeating: " ", count: width - text.count)
}

private func truncate(_ text: String, to maxChars: Int) -> String {
    if text.count <= maxChars { return text }
    guard maxChars > 1 else { return String(text.prefix(maxChars)) }
    return String(text.prefix(maxChars - 1)) + "…"
}
