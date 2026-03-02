import Foundation
import Darwin

final class InputComposer {
    private var originalTermios = termios()
    private var rawEnabled = false
    private var history: [String] = []
    private var historyIndex: Int?

    func addHistory(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.append(line)
        if history.count > 200 { history.removeFirst(history.count - 200) }
        historyIndex = nil
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
                handleEscape(chars: &chars, cursor: &cursor)
            default:
                if byte >= 32 {
                    chars.insert(Character(UnicodeScalar(byte)), at: cursor)
                    cursor += 1
                }
            }
        }
    }

    private func handleEscape(chars: inout [Character], cursor: inout Int) {
        guard let b1 = readByte(), b1 == 91 else { return }
        guard let b2 = readByte() else { return }

        switch b2 {
        case 65: // up
            if !history.isEmpty {
                if historyIndex == nil { historyIndex = history.count - 1 }
                else if let idx = historyIndex, idx > 0 { historyIndex = idx - 1 }
                if let idx = historyIndex {
                    chars = Array(history[idx])
                    cursor = chars.count
                }
            }
        case 66: // down
            if let idx = historyIndex {
                if idx < history.count - 1 {
                    historyIndex = idx + 1
                    chars = Array(history[historyIndex!])
                    cursor = chars.count
                } else {
                    historyIndex = nil
                    chars = []
                    cursor = 0
                }
            }
        case 67: // right
            cursor = min(chars.count, cursor + 1)
        case 68: // left
            cursor = max(0, cursor - 1)
        case 72: // home
            cursor = 0
        case 70: // end
            cursor = chars.count
        case 51: // delete
            _ = readByte() // swallow ~
            if cursor < chars.count { chars.remove(at: cursor) }
        default:
            break
        }
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

    private func readByte() -> UInt8? {
        var c: UInt8 = 0
        let n = read(STDIN_FILENO, &c, 1)
        return n == 1 ? c : nil
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
