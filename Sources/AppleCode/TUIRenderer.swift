import Foundation
import Darwin

final class TUIRenderer {
    private(set) var theme: TUITheme
    private let capabilities: TerminalCapabilities
    private(set) var lastRenderedLines = 0

    init(theme: TUITheme, capabilities: TerminalCapabilities) {
        self.theme = theme
        self.capabilities = capabilities
    }

    func setTheme(_ theme: TUITheme) {
        self.theme = theme
    }

    func terminalSize() -> (width: Int, height: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
            return (max(40, Int(w.ws_col)), max(12, Int(w.ws_row)))
        }
        return (100, 30)
    }

    func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }

    func clearComposerArea() {
        guard lastRenderedLines > 0 else { return }
        for _ in 0..<lastRenderedLines {
            print("\u{001B}[2K\u{001B}[1A", terminator: "")
        }
        print("\u{001B}[2K\r", terminator: "")
        lastRenderedLines = 0
    }

    func renderBannerAnimated() {
        let c1 = TUI.Colors.brightCyan
        let c2 = TUI.Colors.brightMagenta
        let c3 = TUI.Colors.brightWhite
        let c4 = TUI.Colors.brightWhite
        let r = TUI.reset

        print("\(c1)╭──────────────────────────────────────────────────────────────────────────────╮\(r)")
        print("\(c1)│\(r) \(c1)▒▓█\(r)  \(c2)\(TUI.bold)A P P L E   C O D E\(r)  \(c1)█▓▒\(r)  \(c4)\(TUI.bold):: on-device neural shell ::\(r) \(c1)│\(r)")
        print("\(c1)├──────────────────────────────────────────────────────────────────────────────┤\(r)")
        print("\(c1)│\(r) \(c3)╔═╗╔═╗╔═╗╦  ╔═╗   ╔═╗╔═╗╔╦╗╔═╗\(r)   \(c4)AI.WORKFLOW.PIPELINE\(r)      \(c1)│\(r)")
        print("\(c1)│\(r) \(c3)╠═╣╠═╝╠═╝║  ║╣    ║  ║ ║ ║║║╣ \(r)   \(c4)TOOLS • NOTES • WEB • PDF\(r)   \(c1)│\(r)")
        print("\(c1)│\(r) \(c3)╩ ╩╩  ╩  ╩═╝╚═╝   ╚═╝╚═╝═╩╝╚═╝\(r)   \(c4)SESSION.MEMORY.ACTIVE\(r)      \(c1)│\(r)")
        print("\(c1)├──────────────────────────────────────────────────────────────────────────────┤\(r)")
        print("\(c1)│\(r) \(c2)>\(r) \(theme.muted)Type /help • Enter submit • Ctrl+J newline • /theme\(r)                  \(c1)│\(r)")
        print("\(c1)╰──────────────────────────────────────────────────────────────────────────────╯\(r)\n")
    }

    func renderComposer(buffer: String, cursorIndex: Int, cwd: String, model: String = "on-device") {
        clearComposerArea()

        let size = terminalSize()
        let inner = max(20, size.width - 6) // account for borders + margins
        let bodyRows = max(3, min(6, Int(Double(size.height) * 0.25)))

        let wrappedResult = wrapWithCursor(buffer: buffer, cursorIndex: cursorIndex, width: inner)
        let wrapped = wrappedResult.lines
        let cursorRow = wrappedResult.cursorRow
        let cursorCol = wrappedResult.cursorCol

        let maxStart = max(0, wrapped.count - bodyRows)
        let visibleStart = min(max(0, cursorRow - bodyRows + 1), maxStart)
        var visible = Array(wrapped.dropFirst(visibleStart).prefix(bodyRows))
        while visible.count < bodyRows { visible.append("") }
        let cursorVisibleRow = max(0, min(bodyRows - 1, cursorRow - visibleStart))

        let b = theme.border
        let cwdCompact = truncateMiddle(cwd, maxChars: max(10, inner - 18))
        let headerPlain = "[\(model)] [\(cwdCompact)]"
        let headerText = clip(headerPlain, width: inner)
        let headerPad = max(0, inner - headerText.count)

        print("\(theme.primary)\(b.tl)\(String(repeating: b.h, count: inner + 2))\(b.tr)\(TUI.reset)")
        print("\(theme.primary)\(b.v)\(TUI.reset) \(theme.accent)\(headerText)\(TUI.reset)\(String(repeating: " ", count: headerPad)) \(theme.primary)\(b.v)\(TUI.reset)")

        for line in visible {
            let clipped = clip(line, width: inner)
            let pad = max(0, inner - clipped.count)
            print("\(theme.primary)\(b.v)\(TUI.reset) \(clipped)\(String(repeating: " ", count: pad)) \(theme.primary)\(b.v)\(TUI.reset)")
        }

        let hint = "Enter submit | Ctrl+J newline | /theme"
        let hintText = clip(hint, width: inner)
        let hintPad = max(0, inner - hintText.count)
        print("\(theme.primary)\(b.v)\(TUI.reset) \(theme.muted)\(hintText)\(TUI.reset)\(String(repeating: " ", count: hintPad)) \(theme.primary)\(b.v)\(TUI.reset)")
        print("\(theme.primary)\(b.bl)\(String(repeating: b.h, count: inner + 2))\(b.br)\(TUI.reset)")

        let totalLines = bodyRows + 4
        let targetLine = 2 + cursorVisibleRow // top border + header row + body offset
        let moveUp = max(0, totalLines - 1 - targetLine)
        if moveUp > 0 { print("\u{001B}[\(moveUp)A", terminator: "") }
        print("\r\u{001B}[\(min(inner, cursorCol) + 2)C", terminator: "")
        fflush(stdout)
        lastRenderedLines = totalLines
    }

    private func wrapWithCursor(buffer: String, cursorIndex: Int, width: Int) -> (lines: [String], cursorRow: Int, cursorCol: Int) {
        let chars = Array(buffer)
        var lines: [String] = [""]
        var row = 0, col = 0
        var i = 0
        while i < chars.count {
            if i == cursorIndex {
                // Keep cursor tracked before consuming char at cursor index.
            }
            let ch = chars[i]
            if ch == "\n" {
                row += 1
                col = 0
                lines.append("")
            } else {
                lines[row].append(ch)
                col += 1
                if col >= width {
                    row += 1
                    col = 0
                    lines.append("")
                }
            }
            i += 1
        }

        // Recompute cursor row/col by replaying up to cursorIndex.
        var cRow = 0, cCol = 0
        i = 0
        while i < min(cursorIndex, chars.count) {
            let ch = chars[i]
            if ch == "\n" {
                cRow += 1
                cCol = 0
            } else {
                cCol += 1
                if cCol >= width {
                    cRow += 1
                    cCol = 0
                }
            }
            i += 1
        }
        if lines.isEmpty { lines = [""] }
        return (lines, cRow, cCol)
    }

    private func clip(_ text: String, width: Int) -> String {
        if text.count <= width { return text }
        return String(text.prefix(width))
    }

    private func truncateMiddle(_ text: String, maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        let keep = max(4, (maxChars - 1) / 2)
        let prefix = text.prefix(keep)
        let suffix = text.suffix(max(2, maxChars - keep - 1))
        return "\(prefix)…\(suffix)"
    }
}
