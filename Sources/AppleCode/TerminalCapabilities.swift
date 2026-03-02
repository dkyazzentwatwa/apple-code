import Foundation
import Darwin

struct TerminalCapabilities {
    let supportsAdvancedUI: Bool
    let supportsUnicode: Bool
    let supportsTrueColor: Bool
    let supportsModifiedEnter: Bool

    static func detect() -> TerminalCapabilities {
        let isTTY = isatty(fileno(stdin)) == 1 && isatty(fileno(stdout)) == 1
        let term = (ProcessInfo.processInfo.environment["TERM"] ?? "").lowercased()
        let colorterm = (ProcessInfo.processInfo.environment["COLORTERM"] ?? "").lowercased()
        let lang = (ProcessInfo.processInfo.environment["LC_ALL"]
            ?? ProcessInfo.processInfo.environment["LC_CTYPE"]
            ?? ProcessInfo.processInfo.environment["LANG"]
            ?? "").lowercased()
        let termProgram = (ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "").lowercased()

        let unicode = lang.contains("utf-8") || lang.contains("utf8")
        let trueColor = colorterm.contains("truecolor") || colorterm.contains("24bit") || term.contains("direct")
        let advanced = isTTY && term != "dumb" && !term.isEmpty
        let modifiedEnter = termProgram.contains("iterm") || term.contains("kitty") || term.contains("wezterm")

        return TerminalCapabilities(
            supportsAdvancedUI: advanced,
            supportsUnicode: unicode,
            supportsTrueColor: trueColor,
            supportsModifiedEnter: modifiedEnter
        )
    }
}
