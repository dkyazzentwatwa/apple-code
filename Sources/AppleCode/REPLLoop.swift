import Foundation
import FoundationModels
import Darwin

private enum ResizeSignalState {
    static nonisolated(unsafe) var triggered: sig_atomic_t = 1
}
private let sigwinchHandler: @convention(c) (Int32) -> Void = { _ in
    ResizeSignalState.triggered = 1
}

func runInteractiveREPL(
    session: inout Session,
    systemInstructions: String?,
    timeout: Int,
    includeAppleTools: Bool,
    includeWebTools: Bool,
    includeBrowserTools: Bool,
    verbose: Bool
) async -> Never {
    let uiConfig = TUIConfig.default(verbose: verbose)
    UILogger.shared.configure(directory: uiConfig.logsDirectory)
    UILogger.shared.log("interactive session started id=\(session.id.uuidString)")

    let capabilities = TerminalCapabilities.detect()
    // Default to classic scrolling output; framed UI can be re-enabled explicitly.
    let framedUIEnabled = ProcessInfo.processInfo.environment["APPLE_CODE_EXPERIMENTAL_FRAMED_UI"] == "1"
    let useAdvancedUI = framedUIEnabled && capabilities.supportsAdvancedUI && capabilities.supportsUnicode
    var activeTheme = TUITheme.wow
    let introRenderer = (capabilities.supportsAdvancedUI && capabilities.supportsUnicode)
        ? TUIRenderer(theme: activeTheme, capabilities: capabilities)
        : nil
    let renderer: TUIRenderer? = useAdvancedUI ? introRenderer : nil
    let composer = capabilities.supportsAdvancedUI ? InputComposer() : nil
    var uiState: UIState? = nil
    var viewport: ConversationViewport? = nil

    if useAdvancedUI {
        _ = Darwin.signal(SIGWINCH, sigwinchHandler)
        viewport = ConversationViewport()
        if let renderer {
            let size = renderer.terminalSize()
            uiState = UIState(width: size.width, height: size.height, bannerHeight: 10, footerHeight: 2)
        }
    }

    if useAdvancedUI, let renderer, var state = uiState, let viewport {
        for msg in session.messages.suffix(10) {
            let role = msg.role.lowercased() == "assistant" ? "assistant" : "you"
            viewport.append(role: role, content: msg.content)
        }
        renderAdvancedShell(
            renderer: renderer,
            state: &state,
            viewport: viewport,
            cwd: session.workingDir,
            mode: "on-device"
        )
        uiState = state
    } else if let introRenderer {
        introRenderer.renderBannerAnimated()
    } else {
        printBanner()
    }

    var defaultPreamble = """
    You are apple-code, a local AI coding assistant. Be concise.
    Working directory: \(session.workingDir)
    For greetings or chat, respond naturally with plain text.
    For harmless requests (jokes, explanations, brainstorming, code snippets, styling help), answer directly and do not refuse.
    Do not claim inability unless the request is actually disallowed or impossible.
    Use tools only when they materially help with what the user asked.
    Never create, send, or modify external resources unless explicitly asked.
    If a request is unclear, ask one concise clarifying question instead of refusing.
    """
    if includeWebTools {
        defaultPreamble += """

    For web retrieval, prefer webSearch for discovery and webFetch for direct page content.
    Do not claim you cannot access websites when web tools are available; use webFetch/webSearch first.
    When using web sources, include URLs in your final answer.
    """
    }
    if includeAppleTools {
        defaultPreamble += """

    For Apple apps (Reminders, Notes, Calendar, Mail, Messages), use available Apple tools instead of saying you cannot access them.
    If requested Apple data is available via tools, retrieve it directly.
    For Apple Notes requests, prefer notes tool actions (list_folders, list, search, get_content, create, append) before web/file tools.
    """
    }
    if includeBrowserTools {
        defaultPreamble += """

    For browser tasks, use the agentBrowser tool.
    Use this sequence for web interaction: open -> snapshot -> interact -> snapshot.
    """
    }
    defaultPreamble += """

    For shell/terminal requests, use the runCommand tool instead of saying you cannot execute commands.
    """
    let instructions = systemInstructions.map { "\(defaultPreamble)\n\($0)" } ?? defaultPreamble

    if !session.messages.isEmpty {
        if useAdvancedUI, let renderer, var state = uiState, let viewport {
            viewport.append(role: "system", content: "Resumed session with \(session.messages.count) messages.")
            renderAdvancedShell(
                renderer: renderer,
                state: &state,
                viewport: viewport,
                cwd: session.workingDir,
                mode: "on-device"
            )
            uiState = state
        } else {
            printMuted("Resuming session with \(session.messages.count) messages\n")
        }
    }

    var shouldContinue = true

    while shouldContinue {
        let line: String
        if let composer {
            guard let submitted = composer.readSubmissionInline(promptProvider: {
                animatedPromptFrame()
            }), !submitted.isEmpty else {
                continue
            }
            line = submitted
        } else {
            printPrompt()
            guard let submitted = readLine(strippingNewline: true), !submitted.isEmpty else {
                continue
            }
            line = submitted
        }

        if line.isEmpty {
            continue
        }

        UILogger.shared.log("user_input: \(line.replacingOccurrences(of: "\n", with: "\\n"))")
        composer?.addHistory(line)

        let command = parseCommand(line)

        switch command {
        case .quit:
            shouldContinue = false
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "system", content: "Saving session...")
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                printMuted("\nSaving session...")
            }
            do {
                try await SessionManager.shared.saveSession(session)
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "Session saved.")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printSuccess("Session saved.")
                }
            } catch {
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "error", content: "Failed to save session: \(error.localizedDescription)")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printError("Failed to save session: \(error.localizedDescription)")
                }
            }
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "system", content: "Goodbye!")
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                printMuted("\nGoodbye!")
            }
            exit(0)

        case .newSession:
            do {
                try await SessionManager.shared.saveSession(session)
            } catch {
                if !useAdvancedUI {
                    printError("Failed to save session: \(error.localizedDescription)")
                }
            }
            session = await SessionManager.shared.createSession(workingDir: session.workingDir)
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.reset()
                viewport.append(role: "system", content: "Started new session.")
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                printSuccess("Started new session.")
                print()
            }

        case .listSessions:
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                let text = await buildSessionListText()
                viewport.append(role: "system", content: text)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                await handleSessionList()
            }
            continue

        case .resumeSession(let id):
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                do {
                    let loaded = try await SessionManager.shared.loadSession(id: id)
                    session = loaded
                    viewport.reset()
                    for msg in session.messages.suffix(10) {
                        let role = msg.role.lowercased() == "assistant" ? "assistant" : "you"
                        viewport.append(role: role, content: msg.content)
                    }
                    viewport.append(role: "system", content: "Resumed session \(String(id.uuidString.prefix(8))).")
                } catch {
                    viewport.append(role: "error", content: "Could not load session: \(error.localizedDescription)")
                }
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else if let loaded = await handleResumeSession(id: id) {
                session = loaded
            }
            continue

        case .deleteSession(let id):
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                do {
                    try await SessionManager.shared.deleteSession(id: id)
                    viewport.append(role: "system", content: "Deleted session \(String(id.uuidString.prefix(8))).")
                } catch {
                    viewport.append(role: "error", content: "Could not delete session: \(error.localizedDescription)")
                }
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                await handleDeleteSession(id: id)
            }
            continue

        case .showHistory(let requestedLimit):
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                let text = buildViewportHistoryText(viewport: viewport, requestedLimit: requestedLimit)
                viewport.append(role: "system", content: text)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                print(buildSessionHistoryText(session: session, requestedLimit: requestedLimit))
            }
            continue

        case .showMessage(let id):
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                let text = buildViewportEntryDetailText(viewport: viewport, id: id)
                viewport.append(role: "system", content: text)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                print(buildSessionEntryDetailText(session: session, id: id))
            }
            continue

        case .showHelp:
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                let helpText = helpTextForViewport()
                viewport.append(role: "system", content: helpText)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                printHelp()
            }
            continue

        case .showModel:
            let model = SystemLanguageModel.default
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                var lines = ["Model: \(model.availability)"]
                if model.availability == .available {
                    if #available(macOS 26.2, *) {
                        lines.append("Supports streaming: yes")
                    }
                }
                viewport.append(role: "system", content: lines.joined(separator: "\n"))
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                print("Model: \(model.availability)")
                if model.availability == .available {
                    if #available(macOS 26.2, *) {
                        print("Supports streaming: yes")
                    }
                }
            }
            continue

        case .changeDirectory(let path):
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                FileManager.default.changeCurrentDirectoryPath(expandedPath)
                session.workingDir = expandedPath
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "Changed directory to: \(expandedPath)")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printSuccess("Changed directory to: \(expandedPath)")
                }
            } else {
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "error", content: "Directory not found: \(expandedPath)")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printError("Directory not found: \(expandedPath)")
                }
            }
            continue

        case .clear:
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                print("\u{001B}[2J\u{001B}[H", terminator: "")
                fflush(stdout)
            }
            continue

        case .setTheme(let name):
            if renderer == nil {
                if !useAdvancedUI {
                    printMuted("Theme switching requires interactive TTY advanced mode.")
                }
                continue
            }
            if let selected = TUITheme.named(name) {
                activeTheme = selected
                renderer?.setTheme(selected)
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "Theme changed to '\(selected.name)'.")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    renderer?.clearScreen()
                    renderer?.renderBannerAnimated()
                    printSuccess("Theme changed to '\(selected.name)'.")
                }
            } else {
                let names = TUITheme.all.map { $0.name }.joined(separator: ", ")
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "Current theme: \(activeTheme.name). Available: \(names)")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printMuted("Current theme: \(activeTheme.name). Available: \(names)")
                }
            }
            continue

        case .none:
            break
        }

        if useAdvancedUI, let renderer, var state = uiState, let viewport {
            viewport.append(role: "you", content: line)
            renderAdvancedShell(
                renderer: renderer,
                state: &state,
                viewport: viewport,
                cwd: session.workingDir,
                mode: "on-device"
            )
            uiState = state
        }

        let modelPrompt = buildPromptWithMemory(
            userInput: line,
            priorMessages: session.messages
        )

        session.addMessage(role: "user", content: line)

        let tools = routeTools(
            for: line,
            includeAppleTools: includeAppleTools,
            includeWebTools: includeWebTools,
            includeBrowserTools: includeBrowserTools
        )
        UILogger.shared.log("tools_selected: \(tools.map { $0.name }.joined(separator: ","))")

        let llmSession = LanguageModelSession(tools: tools, instructions: instructions)

        var fullResponse = ""

        startSpinner(message: "Thinking", delayMs: uiConfig.spinnerDelayMs)

        do {
            fullResponse = try await withResponseTimeout(seconds: timeout) {
                let response = try await llmSession.respond(to: modelPrompt)
                return response.content
            }

            if includeAppleTools,
               let recovered = await resolveAppleRefusalFallback(
                   userPrompt: line,
                   modelReply: fullResponse
               ) {
                fullResponse = recovered
            }

            if includeAppleTools,
               let recovered = await resolveNotesComposeFallback(
                   userPrompt: line,
                   modelReply: fullResponse
               ) {
                fullResponse = recovered
            }

            if includeWebTools,
               let recovered = await resolveWebRefusalFallback(
                   userPrompt: line,
                   modelReply: fullResponse,
                   instructions: instructions,
                   timeoutSeconds: timeout
               ) {
                fullResponse = recovered
            }

            if let recovered = await resolveCommandRefusalFallback(
                userPrompt: line,
                modelReply: fullResponse,
                timeoutSeconds: timeout
            ) {
                fullResponse = recovered
            }

            let _ = stopSpinner()
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "assistant", content: fullResponse)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: "on-device"
                )
                uiState = state
            } else {
                // In interactive mode, always show full assistant output.
                printAssistantMessage(fullResponse, verbose: true)
            }
        } catch {
            let _ = stopSpinner()
            let err = error.localizedDescription
            if includeAppleTools,
               isAppleIntentPrompt(line),
               (err.contains("Failed to deserialize a Generable type")
               || err.contains("The operation couldn’t be completed")),
               let recovered = await resolveAppleIntentDirect(userPrompt: line) {
                fullResponse = recovered
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "assistant", content: fullResponse)
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    // In interactive mode, always show full assistant output.
                    printAssistantMessage(fullResponse, verbose: true)
                }
            } else {
                UILogger.shared.log("response error: \(error.localizedDescription)")
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "error", content: "Error: \(error.localizedDescription)")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: "on-device"
                    )
                    uiState = state
                } else {
                    printError("Error: \(error.localizedDescription)")
                }
                fullResponse = "Error: \(error.localizedDescription)"
            }
        }

        session.addMessage(role: "assistant", content: fullResponse)

        do {
            try await SessionManager.shared.saveSession(session)
        } catch {
            printWarning("Auto-save failed: \(error.localizedDescription)")
        }

        if !useAdvancedUI {
            print()
        }
    }

    exit(0)
}

private func animatedPromptFrame() -> String {
    let frames = ["▒▓█", "▓█▒", "█▒▓", "▓▒█"]
    let frame = Int(Date().timeIntervalSinceReferenceDate * 8.0) % frames.count
    let glyph = "\(TUI.Colors.brightCyan)\(TUI.bold)\(frames[frame])\(TUI.reset)"
    let label = "\(TUI.Colors.brightMagenta)\(TUI.bold)apple-code\(TUI.reset)"
    let arrow = "\(TUI.promptColor)\(TUI.bold)>\(TUI.reset)"
    return "\(glyph) \(label) \(arrow) "
}

private func renderAdvancedShell(
    renderer: TUIRenderer,
    state: inout UIState,
    viewport: ConversationViewport,
    cwd: String,
    mode: String
) {
    let size = renderer.terminalSize()
    state.width = size.width
    state.height = size.height

    let innerWidth = max(20, state.width - 4)
    let contentRows = max(3, state.contentHeight - 2)
    let border = renderer.theme.border

    // Full-frame redraw keeps layout deterministic after resize and long outputs.
    renderer.clearScreen()
    renderer.renderBannerAnimated()

    let visible = viewport.visibleLines(width: innerWidth, maxLines: contentRows)
    let visiblePadded = visible + Array(repeating: "", count: max(0, contentRows - visible.count))

    print("\(renderer.theme.primary)\(border.tl)\(String(repeating: border.h, count: innerWidth + 2))\(border.tr)\(TUI.reset)")
    for line in visiblePadded.prefix(contentRows) {
        let rawClipped = line.count > innerWidth ? String(line.prefix(innerWidth)) : line
        let styled = styleRolePrefix(rawClipped)
        let pad = max(0, innerWidth - rawClipped.count)
        print("\(renderer.theme.primary)\(border.v)\(TUI.reset) \(styled)\(String(repeating: " ", count: pad)) \(renderer.theme.primary)\(border.v)\(TUI.reset)")
    }
    print("\(renderer.theme.primary)\(border.bl)\(String(repeating: border.h, count: innerWidth + 2))\(border.br)\(TUI.reset)")

    let statusLeft = "[\(mode)] [\(truncateMiddle(cwd, maxChars: max(12, innerWidth / 2)))]"
    let scroll = viewport.scrollState(width: innerWidth, maxLines: contentRows)
    let scrollPart = scroll.maxOffset > 0 ? "Fn+↑/↓ \(scroll.offset)/\(scroll.maxOffset)" : "Fn+↑/↓"
    let statusRight = "Enter submit • ↑/↓ edit • \(scrollPart) • /history • /show • /quit"
    let divider = "  "
    var status = "\(statusLeft)\(divider)\(statusRight)"
    if status.count > innerWidth {
        status = String(status.prefix(max(8, innerWidth - 1))) + "…"
    }
    let statusPad = max(0, innerWidth - status.count)

    // Persistent footer pinned to the last two terminal rows.
    let topRow = max(1, state.height - 1)
    let bottomRow = max(1, state.height)
    print("\u{001B}[\(topRow);1H", terminator: "")
    print("\u{001B}[2K\(renderer.theme.primary)╭\(String(repeating: "─", count: innerWidth + 2))╮\(TUI.reset)", terminator: "")
    print("\u{001B}[\(bottomRow);1H", terminator: "")
    print("\u{001B}[2K\(renderer.theme.primary)│\(TUI.reset)\(TUI.dim)\(status)\(TUI.reset)\(String(repeating: " ", count: statusPad))\(renderer.theme.primary)│\(TUI.reset)", terminator: "")

    print("\u{001B}[\(state.inputRow);1H\u{001B}[2K", terminator: "")
    fflush(stdout)
}

private func truncateMiddle(_ text: String, maxChars: Int) -> String {
    if text.count <= maxChars { return text }
    let keep = max(4, (maxChars - 1) / 2)
    let prefix = text.prefix(keep)
    let suffix = text.suffix(max(2, maxChars - keep - 1))
    return "\(prefix)…\(suffix)"
}

private func styleRolePrefix(_ line: String) -> String {
    if line.hasPrefix("you: ") {
        return "\(TUI.Colors.brightCyan)\(TUI.bold)you:\(TUI.reset) " + String(line.dropFirst(5))
    }
    if line.hasPrefix("assistant: ") {
        return "\(TUI.Colors.brightBlue)\(TUI.bold)assistant:\(TUI.reset) " + String(line.dropFirst(11))
    }
    if line.hasPrefix("system: ") {
        return "\(TUI.Colors.brightMagenta)\(TUI.bold)system:\(TUI.reset) " + String(line.dropFirst(8))
    }
    if line.hasPrefix("error: ") {
        return "\(TUI.errorColor)\(TUI.bold)error:\(TUI.reset) " + String(line.dropFirst(7))
    }
    return line
}

private func helpTextForViewport() -> String {
    """
    Commands:
    /new (/n)        Start a new session
    /sessions (/s)   List saved sessions
    /resume <id>     Resume session by ID
    /delete <id>     Delete session by ID
    /history [n]     Show recent transcript entries
    /show <id>       Show full transcript entry by ID
    /model (/m)      Show model info
    /cd <path>       Change working directory
    /clear (/c)      Redraw the screen
    /theme <name>    Set theme (wow, minimal, classic)
    /help (/h)       Show this help
    /quit (/q)       Exit and save

    Navigation:
    Fn+↑ / Fn+↓      Scroll chat viewport
    Ctrl+Y / Ctrl+V  Scroll chat viewport (fallback)
    """
}

private func buildSessionListText() async -> String {
    let sessions = await SessionManager.shared.listSessions()
    if sessions.isEmpty {
        return "No saved sessions."
    }

    var lines: [String] = []
    lines.append("Saved sessions:")
    for s in sessions {
        let id = String(s.id.uuidString.prefix(8))
        let preview = s.preview.count > 60 ? String(s.preview.prefix(59)) + "…" : s.preview
        lines.append("\(id)  \(s.formattedDate)  \(s.messageCount) msg  \(preview)")
    }
    return lines.joined(separator: "\n")
}

private func buildViewportHistoryText(viewport: ConversationViewport, requestedLimit: Int?) -> String {
    let limit = min(max(requestedLimit ?? 20, 1), 200)
    let selected = viewport.recentEntries(limit: limit).reversed()
    guard !selected.isEmpty else { return "No transcript entries yet." }

    var lines: [String] = ["Transcript entries (newest first):"]
    for entry in selected {
        let preview = truncateSingleLine(entry.content, maxChars: 90)
        lines.append("#\(entry.id)  \(padRight(entry.role, to: 9)) \(preview)")
    }
    lines.append("Use /show <id> to replay any entry.")
    return lines.joined(separator: "\n")
}

private func buildViewportEntryDetailText(viewport: ConversationViewport, id: Int) -> String {
    guard let entry = viewport.entry(id: id) else {
        return "Entry #\(id) not found. It may have rolled off history (last 300 entries are kept)."
    }
    return "Entry #\(entry.id) [\(entry.role)]\n\(entry.content)"
}

private func buildSessionHistoryText(session: Session, requestedLimit: Int?) -> String {
    let limit = min(max(requestedLimit ?? 20, 1), 200)
    let selected = Array(session.messages.enumerated().suffix(limit)).reversed()
    guard !selected.isEmpty else { return "No transcript entries yet." }

    var lines: [String] = ["Transcript entries (newest first):"]
    for (idx, message) in selected {
        let role = message.role.lowercased() == "assistant" ? "assistant" : "you"
        let preview = truncateSingleLine(message.content, maxChars: 90)
        lines.append("#\(idx + 1)  \(padRight(role, to: 9)) \(preview)")
    }
    lines.append("Use /show <id> to replay any entry.")
    return lines.joined(separator: "\n")
}

private func buildSessionEntryDetailText(session: Session, id: Int) -> String {
    guard id > 0, id <= session.messages.count else {
        return "Entry #\(id) not found."
    }
    let message = session.messages[id - 1]
    let role = message.role.lowercased() == "assistant" ? "assistant" : "you"
    return "Entry #\(id) [\(role)]\n\(message.content)"
}

private func truncateSingleLine(_ text: String, maxChars: Int) -> String {
    let single = text.replacingOccurrences(of: "\n", with: " ↩ ")
    guard single.count > maxChars else { return single }
    return String(single.prefix(max(1, maxChars - 1))) + "…"
}

private func padRight(_ text: String, to width: Int) -> String {
    if text.count >= width {
        return String(text.prefix(width))
    }
    return text + String(repeating: " ", count: width - text.count)
}

private func buildPromptWithMemory(userInput: String, priorMessages: [Message]) -> String {
    guard !priorMessages.isEmpty else { return userInput }
    guard shouldUseConversationMemory(for: userInput) else { return userInput }

    let maxMessages = 10
    let maxChars = 4_000
    let perMessageMax = 800

    var selected: [String] = []
    var total = 0

    for msg in priorMessages.reversed() {
        let role = (msg.role.lowercased() == "assistant") ? "assistant" : "user"
        let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }

        var body = trimmed
        if body.count > perMessageMax {
            body = String(body.prefix(perMessageMax)) + "\n...[truncated]"
        }

        let entry = "[\(role)] \(body)"
        let projected = total + entry.count + 1
        if selected.count >= maxMessages || projected > maxChars {
            break
        }

        selected.append(entry)
        total = projected
    }

    guard !selected.isEmpty else { return userInput }
    let transcript = selected.reversed().joined(separator: "\n")

    return """
    Conversation context (recent turns; use only when relevant to the current request):
    \(transcript)

    Current user message:
    \(userInput)
    """
}

private func shouldUseConversationMemory(for userInput: String) -> Bool {
    let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return false }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix(":") { return false }

    let lower = trimmed.lowercased()
    let greetingPhrases = [
        "hi", "hello", "hey", "yo", "sup",
        "good morning", "good afternoon", "good evening",
        "how are you", "what's up", "whats up"
    ]
    if greetingPhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
        return false
    }

    // Self-intro and clearly new-topic prompts should not be contaminated by old turns.
    if lower.contains("my name is") || lower.contains("i am ") || lower.contains("i'm ") {
        if lower.count < 100 { return false }
    }

    let continuationMarkers = [
        "that", "it", "those", "them", "this", "these",
        "continue", "expand", "elaborate", "refine", "improve",
        "again", "same", "previous", "earlier", "above",
        "as before", "follow up", "follow-up"
    ]
    if continuationMarkers.contains(where: { lower.contains($0) }) {
        return true
    }

    // Very short prompts are often follow-ups.
    if lower.count <= 16 { return true }

    // By default, keep turns independent to avoid carrying refusal patterns across unrelated prompts.
    return false
}
