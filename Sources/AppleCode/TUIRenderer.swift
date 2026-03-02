import Foundation
import Darwin

final class TUIRenderer {
    private(set) var theme: TUITheme
    private let capabilities: TerminalCapabilities
    private(set) var lastRenderedLines = 0
    private(set) var lastBannerHeight = 8

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

    func renderBannerAnimated(
        provider: String = "apple",
        model: String = "on-device",
        uiMode: String = "classic",
        streamState: String = "idle"
    ) {
        let profile = bannerProfile(for: theme)
        let width = terminalSize().width
        let innerWidth = max(50, min(114, width - 2))
        let rule = String(repeating: "─", count: max(16, innerWidth - 2))
        let c1 = profile.borderColor
        let c2 = profile.promptColor
        let logo = rainbowText("A P P L E   C O D E")
        let ascii1 = gradientText("╔═╗╔═╗╔═╗╦  ╔═╗   ╔═╗╔═╗╔╦╗╔═╗", start: profile.asciiAStart, end: profile.asciiAEnd, bold: true)
        let ascii2 = gradientText("╠═╣╠═╝╠═╝║  ║╣    ║  ║ ║ ║║║╣ ", start: profile.asciiBStart, end: profile.asciiBEnd, bold: true)
        let ascii3 = gradientText("╩ ╩╩  ╩  ╩═╝╚═╝   ╚═╝╚═╝═╩╝╚═╝", start: profile.asciiCStart, end: profile.asciiCEnd, bold: true)
        let right1 = gradientText("AI.WORKFLOW.PIPELINE", start: profile.rightAStart, end: profile.rightAEnd, bold: true)
        let right2 = gradientText("TOOLS • NOTES • WEB • PDF", start: profile.rightBStart, end: profile.rightBEnd, bold: true)
        let right3 = gradientText("SESSION.MEMORY.ACTIVE", start: profile.rightCStart, end: profile.rightCEnd, bold: true)
        let statusStrip = "\(chip(text: provider.uppercased(), color: TUI.Colors.brightMagenta)) \(chip(text: model, color: TUI.Colors.brightBlue)) \(chip(text: "UI \(uiMode)", color: TUI.Colors.brightYellow)) \(chip(text: "STREAM \(streamState)", color: TUI.Colors.brightGreen))"
        let r = TUI.reset

        if innerWidth < 88 {
            print("\(c1)╭\(rule)╮\(r)")
            print("\(c1)│\(r) \(c1)▒▓█\(r)  \(logo)\(r)  \(c1)█▓▒\(r)\(String(repeating: " ", count: max(0, innerWidth - 25)))\(c1)│\(r)")
            print("\(c1)│\(r) \(statusStrip)\(String(repeating: " ", count: max(0, innerWidth - 2 - visibleWidth(statusStrip)))) \(c1)│\(r)")
            print("\(c1)│\(r) \(ascii1)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36))) \(c1)│\(r)")
            print("\(c1)│\(r) \(ascii2)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36))) \(c1)│\(r)")
            print("\(c1)│\(r) \(ascii3)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36))) \(c1)│\(r)")
            print("\(c1)│\(r) \(theme.muted)Type /help • /palette • /ui • /theme\(r)\(String(repeating: " ", count: max(0, innerWidth - 37)))\(c1)│\(r)")
            print("\(c1)╰\(rule)╯\(r)\n")
            lastBannerHeight = 8
        } else {
            print("\(c1)╭\(rule)╮\(r)")
            print("\(c1)│\(r) \(c1)▒▓█\(r)  \(logo)\(r)  \(c1)█▓▒\(r)  \(TUI.Colors.brightWhite)\(TUI.bold):: on-device neural shell ::\(r)\(String(repeating: " ", count: max(0, innerWidth - 67)))\(c1)│\(r)")
            print("\(c1)├\(rule)┤\(r)")
            print("\(c1)│\(r) \(ascii1)\(r)   \(right1)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36 - 3 - 20))) \(c1)│\(r)")
            print("\(c1)│\(r) \(ascii2)\(r)   \(right2)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36 - 3 - 24))) \(c1)│\(r)")
            print("\(c1)│\(r) \(ascii3)\(r)   \(right3)\(String(repeating: " ", count: max(0, innerWidth - 2 - 36 - 3 - 21))) \(c1)│\(r)")
            print("\(c1)│\(r) \(statusStrip)\(String(repeating: " ", count: max(0, innerWidth - 2 - visibleWidth(statusStrip)))) \(c1)│\(r)")
            print("\(c1)├\(rule)┤\(r)")
            print("\(c1)│\(r) \(c2)>\(r) \(theme.muted)Type /help • Enter submit • Ctrl+P palette • /theme\(r)\(String(repeating: " ", count: max(0, innerWidth - 57)))\(c1)│\(r)")
            print("\(c1)╰\(rule)╯\(r)\n")
            lastBannerHeight = 9
        }
    }

    func chip(text: String, color: String) -> String {
        "\(TUI.bold)\(color)◉ \(text)\(TUI.reset)"
    }

    private func gradientText(
        _ text: String,
        start: (Int, Int, Int),
        end: (Int, Int, Int),
        bold: Bool = false
    ) -> String {
        let chars = Array(text)
        guard !chars.isEmpty else { return text }

        var out = ""
        let count = max(1, chars.count - 1)
        for (idx, ch) in chars.enumerated() {
            let t = Double(idx) / Double(count)
            let r = mixChannel(start.0, end.0, t: t)
            let g = mixChannel(start.1, end.1, t: t)
            let b = mixChannel(start.2, end.2, t: t)
            out += "\(ansiTrueColor(r: r, g: g, b: b, bold: bold))\(ch)"
        }
        return out + TUI.reset
    }

    private func rainbowText(_ text: String) -> String {
        let palette = [
            TUI.Colors.brightMagenta,
            TUI.Colors.brightCyan,
            TUI.Colors.brightBlue,
            TUI.Colors.brightYellow,
            TUI.Colors.brightGreen,
        ]
        let chars = Array(text)
        guard !chars.isEmpty else { return text }

        var out = ""
        var colorIndex = 0
        for ch in chars {
            if ch == " " {
                out += String(ch)
                continue
            }
            let color = palette[colorIndex % palette.count]
            out += "\(TUI.bold)\(color)\(ch)"
            colorIndex += 1
        }
        return out + TUI.reset
    }

    private struct BannerProfile {
        let borderColor: String
        let promptColor: String
        let asciiAStart: (Int, Int, Int)
        let asciiAEnd: (Int, Int, Int)
        let asciiBStart: (Int, Int, Int)
        let asciiBEnd: (Int, Int, Int)
        let asciiCStart: (Int, Int, Int)
        let asciiCEnd: (Int, Int, Int)
        let rightAStart: (Int, Int, Int)
        let rightAEnd: (Int, Int, Int)
        let rightBStart: (Int, Int, Int)
        let rightBEnd: (Int, Int, Int)
        let rightCStart: (Int, Int, Int)
        let rightCEnd: (Int, Int, Int)
    }

    private func bannerProfile(for theme: TUITheme) -> BannerProfile {
        switch theme.name {
        case "solar":
            return BannerProfile(
                borderColor: TUI.Colors.brightYellow,
                promptColor: TUI.Colors.brightRed,
                asciiAStart: (255, 220, 110), asciiAEnd: (255, 150, 80),
                asciiBStart: (255, 190, 120), asciiBEnd: (255, 95, 95),
                asciiCStart: (255, 225, 130), asciiCEnd: (255, 175, 95),
                rightAStart: (255, 230, 140), rightAEnd: (255, 140, 90),
                rightBStart: (255, 205, 120), rightBEnd: (255, 160, 95),
                rightCStart: (255, 230, 160), rightCEnd: (255, 130, 105)
            )
        case "ocean":
            return BannerProfile(
                borderColor: TUI.Colors.brightBlue,
                promptColor: TUI.Colors.cyan,
                asciiAStart: (120, 210, 255), asciiAEnd: (70, 150, 255),
                asciiBStart: (120, 255, 235), asciiBEnd: (90, 195, 255),
                asciiCStart: (150, 225, 255), asciiCEnd: (90, 170, 255),
                rightAStart: (135, 235, 255), rightAEnd: (90, 165, 255),
                rightBStart: (120, 255, 230), rightBEnd: (110, 200, 255),
                rightCStart: (170, 240, 255), rightCEnd: (120, 185, 255)
            )
        case "forest":
            return BannerProfile(
                borderColor: TUI.Colors.brightGreen,
                promptColor: TUI.Colors.yellow,
                asciiAStart: (145, 240, 145), asciiAEnd: (95, 210, 120),
                asciiBStart: (170, 240, 120), asciiBEnd: (115, 220, 95),
                asciiCStart: (160, 250, 170), asciiCEnd: (100, 205, 120),
                rightAStart: (165, 245, 165), rightAEnd: (120, 220, 120),
                rightBStart: (195, 250, 140), rightBEnd: (135, 220, 110),
                rightCStart: (180, 255, 175), rightCEnd: (110, 215, 130)
            )
        case "minimal":
            return BannerProfile(
                borderColor: TUI.Colors.white,
                promptColor: TUI.Colors.brightBlack,
                asciiAStart: (235, 235, 235), asciiAEnd: (185, 185, 185),
                asciiBStart: (230, 230, 230), asciiBEnd: (170, 170, 170),
                asciiCStart: (245, 245, 245), asciiCEnd: (195, 195, 195),
                rightAStart: (230, 230, 230), rightAEnd: (180, 180, 180),
                rightBStart: (225, 225, 225), rightBEnd: (175, 175, 175),
                rightCStart: (240, 240, 240), rightCEnd: (190, 190, 190)
            )
        case "classic":
            return BannerProfile(
                borderColor: TUI.Colors.cyan,
                promptColor: TUI.Colors.magenta,
                asciiAStart: (120, 220, 255), asciiAEnd: (255, 150, 220),
                asciiBStart: (160, 240, 255), asciiBEnd: (255, 180, 150),
                asciiCStart: (170, 225, 255), asciiCEnd: (255, 210, 150),
                rightAStart: (120, 220, 255), rightAEnd: (255, 175, 220),
                rightBStart: (145, 255, 220), rightBEnd: (255, 205, 145),
                rightCStart: (180, 230, 255), rightCEnd: (170, 255, 200)
            )
        default: // wow
            return BannerProfile(
                borderColor: TUI.Colors.brightCyan,
                promptColor: TUI.Colors.brightGreen,
                asciiAStart: (255, 185, 120), asciiAEnd: (120, 220, 255),
                asciiBStart: (255, 160, 210), asciiBEnd: (120, 255, 210),
                asciiCStart: (170, 210, 255), asciiCEnd: (255, 205, 150),
                rightAStart: (120, 220, 255), rightAEnd: (255, 160, 220),
                rightBStart: (130, 255, 220), rightBEnd: (255, 210, 140),
                rightCStart: (170, 220, 255), rightCEnd: (160, 255, 190)
            )
        }
    }

    private func mixChannel(_ a: Int, _ b: Int, t: Double) -> Int {
        Int(Double(a) + (Double(b - a) * min(max(t, 0.0), 1.0)))
    }

    private func ansiTrueColor(r: Int, g: Int, b: Int, bold: Bool) -> String {
        let color = "\u{001B}[38;2;\(r);\(g);\(b)m"
        return bold ? "\(TUI.bold)\(color)" : color
    }

    private func visibleWidth(_ text: String) -> Int {
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
