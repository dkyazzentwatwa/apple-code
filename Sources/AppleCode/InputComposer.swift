import Foundation
import Darwin

final class InputComposer {
    private enum EscapeAction {
        case none
        case scrollUp
        case scrollDown
        case previousSession
    }

    private enum HistoryRecall {
        case unchanged
        case value(String)
        case clear
    }

    private var originalTermios = termios()
    private var rawEnabled = false
    private let historyLock = NSLock()
    private var history: [String] = []
    private var historyIndex: Int?

    func addHistory(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withHistoryLock {
            history.append(line)
            if history.count > 200 {
                history.removeFirst(history.count - 200)
            }
            historyIndex = nil
        }
    }

    func readSubmission(renderer: TUIRenderer, cwd: String) -> String? {
        guard enableRawMode() else { return readLine(strippingNewline: true) }
        defer { disableRawMode(); renderer.clearComposerArea() }

        var chars: [Character] = []
        var cursor = 0

        while true {
            renderer.renderComposer(buffer: String(chars), cursorIndex: cursor, cwd: cwd)
            guard let byte = readByte() else { continue }

            switch byte {
            case 3: // Ctrl+C
                return "/quit"
            case 10: // Ctrl+J newline fallback
                chars.insert("\n", at: cursor)
                cursor += 1
            case 13: // Enter submit
                let line = String(chars)
                return line.trimmingCharacters(in: .newlines).isEmpty ? nil : line
            case 127, 8: // backspace
                if cursor > 0 {
                    cursor -= 1
                    chars.remove(at: cursor)
                }
            case 1: // Ctrl+A
                cursor = 0
            case 5: // Ctrl+E
                cursor = chars.count
            case 11: // Ctrl+K
                if cursor < chars.count { chars.removeSubrange(cursor..<chars.count) }
            case 21: // Ctrl+U
                if cursor > 0 { chars.removeSubrange(0..<cursor); cursor = 0 }
            case 23: // Ctrl+W
                deleteWordBackward(chars: &chars, cursor: &cursor)
            case 27: // Escape sequence
                _ = handleEscape(chars: &chars, cursor: &cursor)
            default:
                if byte >= 32 {
                    chars.insert(Character(UnicodeScalar(byte)), at: cursor)
                    cursor += 1
                }
            }
        }
    }

    // Stable single-line editor for terminals where full-screen redraw can artifact.
    // Supports arrow keys, history, backspace, and common cursor controls.
    func readSubmissionInline(
        prompt: String = "",
        promptProvider: (() -> String)? = nil,
        onScroll: ((Int) -> Void)? = nil,
        onCommandShortcut: ((String) -> Void)? = nil,
        onSessionNav: ((Int) -> Void)? = nil
    ) -> String? {
        guard enableRawMode() else { return readLine(strippingNewline: true) }
        defer { disableRawMode() }

        var chars: [Character] = []
        var cursor = 0

        while true {
            let currentPrompt = promptProvider?() ?? prompt
            renderInline(prompt: currentPrompt, chars: chars, cursor: cursor)
            guard let byte = readByte(timeoutMs: 100) else { continue }

            switch byte {
            case 3: // Ctrl+C
                print("\r^C\r\n", terminator: "")
                fflush(stdout)
                return "/quit"
            case 10, 13: // Enter
                print("\r\n", terminator: "")
                let line = String(chars)
                return line.trimmingCharacters(in: .newlines).isEmpty ? nil : line
            case 127, 8: // backspace
                if cursor > 0 {
                    cursor -= 1
                    chars.remove(at: cursor)
                }
            case 1: // Ctrl+A
                cursor = 0
            case 5: // Ctrl+E
                cursor = chars.count
            case 11: // Ctrl+K
                if cursor < chars.count { chars.removeSubrange(cursor..<chars.count) }
            case 21: // Ctrl+U
                if cursor > 0 { chars.removeSubrange(0..<cursor); cursor = 0 }
            case 23: // Ctrl+W
                deleteWordBackward(chars: &chars, cursor: &cursor)
            case 25: // Ctrl+Y scroll up (Mac-friendly fallback for PageUp)
                onScroll?(10)
            case 22: // Ctrl+V scroll down (Mac-friendly fallback for PageDown)
                onScroll?(-10)
            case 16: // Ctrl+P command palette
                onCommandShortcut?("/settings")
            case 29: // Ctrl+] quick switch to next session chip
                onSessionNav?(1)
            case 27: // Escape sequence
                switch handleEscape(chars: &chars, cursor: &cursor) {
                case .none:
                    break
                case .scrollUp:
                    onScroll?(10)
                case .scrollDown:
                    onScroll?(-10)
                case .previousSession:
                    onSessionNav?(-1)
                }
            default:
                if byte >= 32 {
                    chars.insert(Character(UnicodeScalar(byte)), at: cursor)
                    cursor += 1
                }
            }
        }
    }

    private func handleEscape(chars: inout [Character], cursor: inout Int) -> EscapeAction {
        guard let b1 = readByte(timeoutMs: 25) else { return .previousSession }

        // VT-style arrows/home/end: ESC O A/B/C/D/H/F
        if b1 == 79 {
            guard let b2 = readByte() else { return .none }
            switch b2 {
            case 65: historyUp(chars: &chars, cursor: &cursor)     // A
            case 66: historyDown(chars: &chars, cursor: &cursor)   // B
            case 67: cursor = min(chars.count, cursor + 1)         // C
            case 68: cursor = max(0, cursor - 1)                   // D
            case 72: cursor = 0                                    // H
            case 70: cursor = chars.count                          // F
            default: break
            }
            return .none
        }

        // CSI-style sequences: ESC [ ...
        guard b1 == 91, let b2 = readByte() else { return .none }
        var seq: [UInt8] = [b2]
        if !(64...126).contains(b2) {
            while let n = readByte() {
                seq.append(n)
                if (64...126).contains(n) { break } // final byte
            }
        }
        guard let final = seq.last else { return .none }
        let sequence = String(bytes: seq, encoding: .ascii) ?? ""

        switch final {
        case 65: // up
            if sequence.contains(";") { return .scrollUp } // modified up arrow (e.g. Option/Shift+Up)
            historyUp(chars: &chars, cursor: &cursor)
        case 66: // down
            if sequence.contains(";") { return .scrollDown } // modified down arrow
            historyDown(chars: &chars, cursor: &cursor)
        case 67: // right
            cursor = min(chars.count, cursor + 1)
        case 68: // left
            cursor = max(0, cursor - 1)
        case 72: // home
            cursor = 0
        case 70: // end
            cursor = chars.count
        case 126: // tilde-terminated CSI
            if sequence.hasPrefix("3") { // delete (3~)
                if cursor < chars.count { chars.remove(at: cursor) }
            } else if sequence.hasPrefix("1") {
                cursor = 0
            } else if sequence.hasPrefix("4") {
                cursor = chars.count
            } else if sequence.hasPrefix("5") {
                return .scrollUp // PageUp (often Fn+Up on macOS terminals)
            } else if sequence.hasPrefix("6") {
                return .scrollDown // PageDown (often Fn+Down)
            }
        default:
            break
        }
        return .none
    }

    private func historyUp(chars: inout [Character], cursor: inout Int) {
        let recalled = withHistoryLock { () -> HistoryRecall in
            guard !history.isEmpty else { return .unchanged }
            if historyIndex == nil {
                historyIndex = history.count - 1
            } else if let idx = historyIndex, idx > 0 {
                historyIndex = idx - 1
            }
            guard let idx = historyIndex, history.indices.contains(idx) else { return .unchanged }
            return .value(history[idx])
        }

        if case .value(let value) = recalled {
            chars = Array(value)
            cursor = chars.count
        }
    }

    private func historyDown(chars: inout [Character], cursor: inout Int) {
        let recalled = withHistoryLock { () -> HistoryRecall in
            guard let idx = historyIndex else { return .unchanged }
            if idx < history.count - 1 {
                let next = idx + 1
                historyIndex = next
                guard history.indices.contains(next) else { return .unchanged }
                return .value(history[next])
            }
            historyIndex = nil
            return .clear
        }

        switch recalled {
        case .value(let value):
            chars = Array(value)
            cursor = chars.count
        case .clear:
            chars = []
            cursor = 0
        case .unchanged:
            break
        }
    }

    private func withHistoryLock<T>(_ body: () -> T) -> T {
        historyLock.lock()
        defer { historyLock.unlock() }
        return body()
    }

    private func deleteWordBackward(chars: inout [Character], cursor: inout Int) {
        guard cursor > 0 else { return }
        var i = cursor
        while i > 0 && chars[i - 1].isWhitespace { i -= 1 }
        while i > 0 && !chars[i - 1].isWhitespace { i -= 1 }
        chars.removeSubrange(i..<cursor)
        cursor = i
    }

    private func enableRawMode() -> Bool {
        guard !rawEnabled else { return true }
        guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else { return false }

        var raw = originalTermios
        cfmakeraw(&raw)

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { return false }
        rawEnabled = true
        return true
    }

    private func disableRawMode() {
        guard rawEnabled else { return }
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        rawEnabled = false
    }

    private func readByte(timeoutMs: Int32? = nil) -> UInt8? {
        if let timeoutMs {
            var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pfd, 1, timeoutMs)
            if ready <= 0 { return nil }
        }
        var c: UInt8 = 0
        let n = read(STDIN_FILENO, &c, 1)
        return n == 1 ? c : nil
    }

    private func renderInline(prompt: String, chars: [Character], cursor: Int) {
        let text = String(chars)
        // Clear current line, re-render prompt + text, then move cursor.
        print("\r\u{001B}[2K\(prompt)\(text)", terminator: "")
        let promptWidth = visibleWidth(prompt)
        let target = max(0, promptWidth + min(cursor, chars.count))
        print("\r\u{001B}[\(target)C", terminator: "")
        fflush(stdout)
    }

    func readMenuSelection(title: String, options: [String]) -> Int? {
        guard !options.isEmpty else { return nil }
        guard enableRawMode() else {
            print("\n\(title)")
            for (index, option) in options.enumerated() {
                print("  \(index + 1). \(option)")
            }
            print("\(TUI.promptColor)Selection>\(TUI.reset) ", terminator: "")
            fflush(stdout)
            guard let raw = readLine(strippingNewline: true),
                  let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parsed > 0, parsed <= options.count else {
                return nil
            }
            return parsed - 1
        }
        defer { disableRawMode() }

        var selected = 0
        while true {
            print("\u{001B}[2J\u{001B}[H", terminator: "")
            writeRawMenuLine("\(TUI.bold)\(title)\(TUI.reset)")
            writeRawMenuLine("")
            for (index, option) in options.enumerated() {
                if index == selected {
                    writeRawMenuLine("\(TUI.Colors.brightCyan)\(TUI.bold)› \(option)\(TUI.reset)")
                } else {
                    writeRawMenuLine("  \(option)")
                }
            }
            writeRawMenuLine("")
            writeRawMenuLine("\(TUI.dim)↑/↓ navigate • Enter select • Esc cancel\(TUI.reset)")
            fflush(stdout)

            guard let byte = readByte() else { continue }
            switch byte {
            case 3:
                return nil
            case 10, 13:
                return selected
            case 27:
                guard let b1 = readByte(timeoutMs: 25) else { return nil }
                guard b1 == 91, let b2 = readByte(timeoutMs: 25) else { return nil }
                if b2 == 65 {
                    selected = max(0, selected - 1)
                } else if b2 == 66 {
                    selected = min(options.count - 1, selected + 1)
                } else {
                    return nil
                }
            default:
                break
            }
        }
    }

    private func writeRawMenuLine(_ line: String) {
        // In raw mode, '\\n' does not return carriage; emit CRLF explicitly.
        print("\u{001B}[2K\r\(line)\r\n", terminator: "")
    }

    private func visibleWidth(_ text: String) -> Int {
        // Strip ANSI CSI sequences so cursor math uses terminal-visible width.
        var width = 0
        var i = text.unicodeScalars.startIndex
        let scalars = text.unicodeScalars

        while i < scalars.endIndex {
            let s = scalars[i]
            if s.value == 0x1B {
                let next = scalars.index(after: i)
                if next < scalars.endIndex, scalars[next].value == 0x5B {
                    var j = scalars.index(after: next)
                    while j < scalars.endIndex {
                        let v = scalars[j].value
                        if (0x40...0x7E).contains(v) {
                            i = scalars.index(after: j)
                            break
                        }
                        j = scalars.index(after: j)
                    }
                    if j >= scalars.endIndex { break }
                    continue
                }
            }
            width += 1
            i = scalars.index(after: i)
        }
        return width
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
