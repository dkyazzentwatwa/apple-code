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
        let lines = [
            "APPLE CODE",
            "local • on-device • tool-enabled"
        ]
        for line in lines {
            print("\(theme.primary)\(TUI.bold)\(line)\(TUI.reset)")
            usleep(45_000)
        }
        print("\(theme.muted)Type /help for commands. Enter submits, Ctrl+J newline.\(TUI.reset)\n")
    }

    func renderComposer(buffer: String, cursorIndex: Int, cwd: String, model: String = "on-device") {
        clearComposerArea()

        let size = terminalSize()
        let width = max(60, size.width - 2)
        let inner = max(20, width - 4)
        let maxComposerHeight = max(6, min(Int(Double(size.height) * 0.30), 12))
        let bodyRows = max(3, maxComposerHeight - 3)

        let wrapped = wrap(buffer: buffer, width: inner)
        let visible = Array(wrapped.suffix(bodyRows))

        let b = theme.border
        let headerText = " \(theme.accent)[\(model)]\(TUI.reset) \(theme.secondary)[\(cwd)]\(TUI.reset) "
        let topPad = max(0, inner - visibleLength(headerText))
        print("\(theme.primary)\(b.tl)\(String(repeating: b.h, count: 1))\(headerText)\(String(repeating: b.h, count: topPad + 1))\(b.tr)\(TUI.reset)")

        for line in visible {
            let clipped = line.count > inner ? String(line.prefix(inner)) : line
            let pad = max(0, inner - visibleLength(clipped))
            print("\(theme.primary)\(b.v)\(TUI.reset) \(clipped)\(String(repeating: " ", count: pad)) \(theme.primary)\(b.v)\(TUI.reset)")
        }

        let hint = "Enter submit • Ctrl+J newline • /theme"
        let hintTrim = hint.count > inner ? String(hint.prefix(inner)) : hint
        let hintPad = max(0, inner - visibleLength(hintTrim))
        print("\(theme.primary)\(b.v)\(TUI.reset) \(theme.muted)\(hintTrim)\(TUI.reset)\(String(repeating: " ", count: hintPad)) \(theme.primary)\(b.v)\(TUI.reset)")
        print("\(theme.primary)\(b.bl)\(String(repeating: b.h, count: inner + 2))\(b.br)\(TUI.reset)", terminator: "")

        let (cursorRow, cursorCol) = cursorPosition(buffer: buffer, cursorIndex: cursorIndex, width: inner, bodyRows: bodyRows)
        let totalLines = visible.count + 3
        let targetLine = 1 + cursorRow
        let moveUp = max(0, totalLines - 1 - targetLine)
        if moveUp > 0 {
            print("\u{001B}[\(moveUp)A", terminator: "")
        }
        print("\r\u{001B}[\(cursorCol + 2)C", terminator: "")
        fflush(stdout)

        lastRenderedLines = totalLines
    }

    private func wrap(buffer: String, width: Int) -> [String] {
        let logicalLines = buffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for line in logicalLines {
            if line.isEmpty {
                out.append("")
                continue
            }
            var current = ""
            for ch in line {
                current.append(ch)
                if current.count >= width {
                    out.append(current)
                    current = ""
                }
            }
            out.append(current)
        }
        return out.isEmpty ? [""] : out
    }

    private func cursorPosition(buffer: String, cursorIndex: Int, width: Int, bodyRows: Int) -> (Int, Int) {
        let chars = Array(buffer)
        var row = 0
        var col = 0
        var i = 0
        while i < min(cursorIndex, chars.count) {
            if chars[i] == "\n" {
                row += 1
                col = 0
            } else {
                col += 1
                if col >= width {
                    row += 1
                    col = 0
                }
            }
            i += 1
        }
        let visibleRow = max(0, min(bodyRows - 1, row - max(0, row - (bodyRows - 1))))
        return (visibleRow, col)
    }

    private func visibleLength(_ s: String) -> Int {
        return s.count
    }
}
