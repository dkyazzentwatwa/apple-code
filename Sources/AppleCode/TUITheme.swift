import Foundation

struct TUITheme {
    let name: String
    let primary: String
    let secondary: String
    let accent: String
    let muted: String
    let border: Border

    struct Border {
        let h: String
        let v: String
        let tl: String
        let tr: String
        let bl: String
        let br: String
    }

    static let wow = TUITheme(
        name: "wow",
        primary: TUI.Colors.brightCyan,
        secondary: TUI.Colors.brightMagenta,
        accent: TUI.Colors.brightWhite,
        muted: TUI.Colors.brightBlack,
        border: .init(h: "═", v: "║", tl: "╔", tr: "╗", bl: "╚", br: "╝")
    )

    static let minimal = TUITheme(
        name: "minimal",
        primary: TUI.Colors.white,
        secondary: TUI.Colors.brightBlack,
        accent: TUI.Colors.cyan,
        muted: TUI.Colors.brightBlack,
        border: .init(h: "─", v: "│", tl: "┌", tr: "┐", bl: "└", br: "┘")
    )

    static let classic = TUITheme(
        name: "classic",
        primary: TUI.Colors.cyan,
        secondary: TUI.Colors.magenta,
        accent: TUI.Colors.white,
        muted: TUI.Colors.brightBlack,
        border: .init(h: "-", v: "|", tl: "+", tr: "+", bl: "+", br: "+")
    )

    static let all: [TUITheme] = [wow, minimal, classic]

    static func named(_ name: String?) -> TUITheme? {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else {
            return nil
        }
        return all.first { $0.name == n }
    }
}
