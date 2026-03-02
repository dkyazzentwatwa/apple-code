import Foundation
import Darwin

struct TUI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let italic = "\u{001B}[3m"
    static let underline = "\u{001B}[4m"

    struct Colors {
        static let black = "\u{001B}[30m"
        static let red = "\u{001B}[31m"
        static let green = "\u{001B}[32m"
        static let yellow = "\u{001B}[33m"
        static let blue = "\u{001B}[34m"
        static let magenta = "\u{001B}[35m"
        static let cyan = "\u{001B}[36m"
        static let white = "\u{001B}[37m"

        static let brightBlack = "\u{001B}[90m"
        static let brightRed = "\u{001B}[91m"
        static let brightGreen = "\u{001B}[92m"
        static let brightYellow = "\u{001B}[93m"
        static let brightBlue = "\u{001B}[94m"
        static let brightMagenta = "\u{001B}[95m"
        static let brightCyan = "\u{001B}[96m"
        static let brightWhite = "\u{001B}[97m"

        static let bgBlack = "\u{001B}[40m"
        static let bgRed = "\u{001B}[41m"
        static let bgGreen = "\u{001B}[42m"
        static let bgYellow = "\u{001B}[43m"
        static let bgBlue = "\u{001B}[44m"
        static let bgMagenta = "\u{001B}[45m"
        static let bgCyan = "\u{001B}[46m"
        static let bgWhite = "\u{001B}[47m"
    }

    static let promptColor = Colors.cyan
    static let userMessageColor = Colors.green
    static let assistantMessageColor = Colors.white
    static let errorColor = Colors.red
    static let warningColor = Colors.yellow
    static let headerColor = Colors.cyan
    static let mutedColor = Colors.brightBlack
    static let successColor = Colors.green
}

let banner = """
\(TUI.Colors.brightCyan)
   AAAAA   PPPPP   PPPPP   L       EEEEE
  A     A  P    P  P    P  L       E
  AAAAAAA  PPPPP   PPPPP   L       EEEE
  A     A  P       P       L       E
  A     A  P       P       LLLLLL  EEEEE
\(TUI.Colors.brightMagenta)
   CCCCC    OOOO   DDDDD   EEEEE
  C        O    O  D    D  E
  C        O    O  D    D  EEEE
  C        O    O  D    D  E
   CCCCC    OOOO   DDDDD   EEEEE
\(TUI.reset)
"""

func printBanner() {
    let isTTY = isatty(fileno(stdout)) == 1
    guard isTTY else { 
        print("apple-code - Local AI Coding Assistant")
        return 
    }
    print(banner)
    print()
    print("\(TUI.Colors.brightBlack)  Type /help for commands or just start chatting!\(TUI.reset)")
    print()
}

func printHeader(model: String? = nil, streaming: Bool = false) {
    let isTTY = isatty(fileno(stdout)) == 1
    guard isTTY else { return }

    let dot = streaming ? "○" : "●"
    let modelInfo = model ?? "on-device"
    let header = "\(TUI.headerColor)\(TUI.bold)\(dot) apple-code · \(modelInfo)\(TUI.reset)"

    print(header)
    print(TUI.mutedColor + String(repeating: "─", count: 40) + TUI.reset)
}

func printPrompt() {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.promptColor)\(TUI.bold)> \(TUI.reset)", terminator: "")
    } else {
        print("> ", terminator: "")
    }
}

func printUserMessage(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.userMessageColor)\(TUI.bold)\(message)\(TUI.reset)")
    } else {
        print(message)
    }
}

func printAssistantMessage(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.assistantMessageColor)\(message)\(TUI.reset)")
    } else {
        print(message)
    }
}

func printError(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.errorColor)Error: \(message)\(TUI.reset)")
    } else {
        print("Error: \(message)")
    }
}

func printWarning(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.warningColor)Warning: \(message)\(TUI.reset)")
    } else {
        print("Warning: \(message)")
    }
}

func printSuccess(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.successColor)\(message)\(TUI.reset)")
    } else {
        print(message)
    }
}

func printMuted(_ message: String) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\(TUI.mutedColor)\(message)\(TUI.reset)")
    } else {
        print(message)
    }
}

func clearLine() {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\u{001B}[2K\r", terminator: "")
    }
}

func moveUp(_ lines: Int = 1) {
    let isTTY = isatty(fileno(stdout)) == 1
    if isTTY {
        print("\u{001B}[\(lines)A", terminator: "")
    }
}

func isInteractive() -> Bool {
    return isatty(fileno(stdin)) == 1 && isatty(fileno(stdout)) == 1
}

final class Spinner {
    static nonisolated(unsafe) let shared = Spinner()
    
    let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    var task: Task<Void, Never>?
    var frameIndex = 0
    private init() {}
}

func startSpinner(message: String = "Thinking") {
    let isTTY = isatty(fileno(stdout)) == 1
    guard isTTY else { return }
    
    Spinner.shared.frameIndex = 0
    Spinner.shared.task = Task { [message] in
        while !Task.isCancelled {
            let frame = Spinner.shared.frames[Spinner.shared.frameIndex % Spinner.shared.frames.count]
            print("\r\(TUI.Colors.brightCyan)\(frame)\(TUI.reset) \(message)...", terminator: "")
            fflush(stdout)
            Spinner.shared.frameIndex += 1
            usleep(80_000)
        }
    }
}

func stopSpinner() {
    Spinner.shared.task?.cancel()
    Spinner.shared.task = nil
    print("\r" + String(repeating: " ", count: 50) + "\r", terminator: "")
}
