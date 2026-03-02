import Foundation
import FoundationModels
import Darwin

private enum ResizeSignalState {
    static nonisolated(unsafe) var triggered: sig_atomic_t = 1
}
private let sigwinchHandler: @convention(c) (Int32) -> Void = { _ in
    ResizeSignalState.triggered = 1
}

private actor StreamEventBuffer {
    private var state: String = "thinking"
    private var preview: String = ""
    private var timeline: [String] = []

    func record(_ event: ModelEvent) {
        switch event {
        case .status(let status):
            state = status
        case .token(let token):
            state = "streaming"
            if preview.count > 1_800 {
                preview.removeFirst(min(400, preview.count))
            }
            preview += token
        case .toolCall(let name):
            state = "tool"
            timeline.append("↗ \(name)")
            if timeline.count > 8 { timeline.removeFirst(timeline.count - 8) }
        case .toolResult(let name, let outputPreview):
            let compact = outputPreview.replacingOccurrences(of: "\n", with: " ")
            timeline.append("↘ \(name): \(compact)")
            if timeline.count > 8 { timeline.removeFirst(timeline.count - 8) }
        case .completed:
            state = "done"
        }
    }

    func snapshot() -> (state: String, preview: String, timeline: [String]) {
        (state, preview, timeline)
    }
}

func runInteractiveREPL(
    session: inout Session,
    initialModelConfig: ModelConfig,
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
    var activeModelConfig = session.modelConfig ?? initialModelConfig
    if session.modelConfig == nil {
        session.modelConfig = activeModelConfig
    }

    let capabilities = TerminalCapabilities.detect()
    let supportsFramedUI = capabilities.supportsAdvancedUI && capabilities.supportsUnicode
    var uiMode = session.uiMode
    var useAdvancedUI = supportsFramedUI && uiMode == .framed
    var activeTheme = TUITheme.named(session.activeThemeName) ?? .wow
    let introRenderer = supportsFramedUI
        ? TUIRenderer(theme: activeTheme, capabilities: capabilities)
        : nil
    var renderer: TUIRenderer? = useAdvancedUI ? introRenderer : nil
    let composer = capabilities.supportsAdvancedUI ? InputComposer() : nil
    var uiState: UIState? = nil
    var viewport: ConversationViewport? = nil
    var streamState = "idle"
    var toolTimeline: [String] = []
    var streamingPreview = ""
    var recentSessions: [SessionSummary] = await SessionManager.shared.listSessions()
    var selectedSessionChipIndex = 0

    if useAdvancedUI {
        _ = Darwin.signal(SIGWINCH, sigwinchHandler)
        viewport = ConversationViewport()
        if let renderer {
            let size = renderer.terminalSize()
            uiState = UIState(width: size.width, height: size.height, bannerHeight: 10, footerHeight: 3)
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
            mode: activeModelConfig.modeLabel,
            modelConfig: activeModelConfig,
            uiMode: uiMode,
            streamState: streamState,
            contextMeter: conversationContextMeter(session: session),
            toolTimeline: toolTimeline,
            streamingPreview: streamingPreview,
            sessions: recentSessions,
            selectedSessionChipIndex: selectedSessionChipIndex
        )
        uiState = state
    } else if let introRenderer {
        introRenderer.renderBannerAnimated(
            provider: activeModelConfig.provider.displayName,
            model: activeModelConfig.model ?? activeModelConfig.modeLabel,
            uiMode: uiMode.rawValue,
            streamState: streamState
        )
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
                mode: activeModelConfig.modeLabel
            )
            uiState = state
        } else {
            printMuted("Resuming session with \(session.messages.count) messages\n")
        }
    }

    while true {
        let sessionWorkingDirSnapshot = session.workingDir
        let contextMeterSnapshot = conversationContextMeter(session: session)
        let line: String
        if let composer {
            guard let submitted = composer.readSubmissionInline(promptProvider: {
                animatedPromptFrame()
            }, onScroll: { delta in
                if useAdvancedUI, let renderer, let viewport, let state = uiState {
                    viewport.scrollBy(delta, width: max(20, state.width - 4), maxLines: max(3, state.contentHeight - 2))
                    var redrawState = state
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &redrawState,
                        viewport: viewport,
                        cwd: sessionWorkingDirSnapshot,
                        mode: activeModelConfig.modeLabel,
                        modelConfig: activeModelConfig,
                        uiMode: uiMode,
                        streamState: streamState,
                        contextMeter: contextMeterSnapshot,
                        toolTimeline: toolTimeline,
                        streamingPreview: streamingPreview,
                        sessions: recentSessions,
                        selectedSessionChipIndex: selectedSessionChipIndex
                    )
                    uiState = redrawState
                }
            }, onCommandShortcut: { command in
                if command == "/settings" {
                    streamState = "settings"
                }
            }, onSessionNav: { delta in
                guard !recentSessions.isEmpty else { return }
                selectedSessionChipIndex = wrappedIndex(selectedSessionChipIndex + delta, count: recentSessions.count)
                streamState = "session"
                if useAdvancedUI, let renderer, let viewport, let state = uiState {
                    var redrawState = state
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &redrawState,
                        viewport: viewport,
                        cwd: sessionWorkingDirSnapshot,
                        mode: activeModelConfig.modeLabel,
                        modelConfig: activeModelConfig,
                        uiMode: uiMode,
                        streamState: streamState,
                        contextMeter: contextMeterSnapshot,
                        toolTimeline: toolTimeline,
                        streamingPreview: streamingPreview,
                        sessions: recentSessions,
                        selectedSessionChipIndex: selectedSessionChipIndex
                    )
                    uiState = redrawState
                }
            }), !submitted.isEmpty else {
                continue
            }
            line = streamState == "settings" ? "/settings" : submitted
            if streamState == "settings" {
                streamState = "idle"
            }
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
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "system", content: "Saving session...")
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: activeModelConfig.modeLabel
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
                        mode: activeModelConfig.modeLabel
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
                        mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
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
            session = await SessionManager.shared.createSession(
                workingDir: session.workingDir,
                modelConfig: activeModelConfig,
                uiMode: uiMode,
                activeThemeName: activeTheme.name
            )
            recentSessions = await SessionManager.shared.listSessions()
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.reset()
                viewport.append(role: "system", content: "Started new session.")
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
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
                    if let pinned = session.modelConfig {
                        activeModelConfig = pinned
                    } else {
                        activeModelConfig = .appleDefault
                        session.modelConfig = activeModelConfig
                    }
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
                    mode: activeModelConfig.modeLabel
                )
                uiState = state
            } else if let loaded = await handleResumeSession(id: id) {
                session = loaded
                if let pinned = session.modelConfig {
                    activeModelConfig = pinned
                } else {
                    activeModelConfig = .appleDefault
                    session.modelConfig = activeModelConfig
                }
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
                    mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
                )
                uiState = state
            } else {
                printHelp()
            }
            continue

        case .showModel:
            let lines: [String]
            do {
                let modelClient = try makeModelClient(config: activeModelConfig)
                lines = modelClient.statusLines()
            } catch {
                lines = [
                    "Provider: \(activeModelConfig.provider.displayName)",
                    "Error: \(error.localizedDescription)",
                ]
            }
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "system", content: lines.joined(separator: "\n"))
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: activeModelConfig.modeLabel
                )
                uiState = state
            } else {
                print(lines.joined(separator: "\n"))
            }
            continue

        case .setUI(let rawArg):
            let value = rawArg?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if value.isEmpty || value == "status" || value == "show" {
                let status = "UI mode: \(uiMode.rawValue)\nAvailable: classic, framed"
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: status)
                    renderAdvancedShell(renderer: renderer, state: &state, viewport: viewport, cwd: session.workingDir, mode: activeModelConfig.modeLabel, modelConfig: activeModelConfig, uiMode: uiMode, streamState: streamState, contextMeter: conversationContextMeter(session: session), toolTimeline: toolTimeline, streamingPreview: streamingPreview, sessions: recentSessions, selectedSessionChipIndex: selectedSessionChipIndex)
                    uiState = state
                } else {
                    printMuted(status)
                }
                continue
            }

            guard let selectedMode = UIMode(rawValue: value) else {
                let err = "Unsupported UI mode '\(value)'. Use classic or framed."
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "error", content: err)
                    renderAdvancedShell(renderer: renderer, state: &state, viewport: viewport, cwd: session.workingDir, mode: activeModelConfig.modeLabel, modelConfig: activeModelConfig, uiMode: uiMode, streamState: streamState, contextMeter: conversationContextMeter(session: session), toolTimeline: toolTimeline, streamingPreview: streamingPreview, sessions: recentSessions, selectedSessionChipIndex: selectedSessionChipIndex)
                    uiState = state
                } else {
                    printError(err)
                }
                continue
            }

            if selectedMode == .framed && !supportsFramedUI {
                let err = "Framed UI requires a Unicode-capable interactive terminal."
                printError(err)
                continue
            }

            uiMode = selectedMode
            session.uiMode = selectedMode
            useAdvancedUI = supportsFramedUI && uiMode == .framed
            if useAdvancedUI {
                if renderer == nil {
                    renderer = introRenderer ?? TUIRenderer(theme: activeTheme, capabilities: capabilities)
                }
                if viewport == nil { viewport = ConversationViewport() }
                if let renderer {
                    let size = renderer.terminalSize()
                    uiState = UIState(width: size.width, height: size.height, bannerHeight: renderer.lastBannerHeight, footerHeight: 3)
                }
                if let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "UI mode switched to framed.")
                    renderAdvancedShell(renderer: renderer, state: &state, viewport: viewport, cwd: session.workingDir, mode: activeModelConfig.modeLabel, modelConfig: activeModelConfig, uiMode: uiMode, streamState: streamState, contextMeter: conversationContextMeter(session: session), toolTimeline: toolTimeline, streamingPreview: streamingPreview, sessions: recentSessions, selectedSessionChipIndex: selectedSessionChipIndex)
                    uiState = state
                }
            } else {
                renderer?.clearScreen()
                printBanner()
                printMuted("UI mode switched to classic.")
            }
            do {
                try await SessionManager.shared.saveSession(session)
            } catch {
                printWarning("Failed to persist UI mode: \(error.localizedDescription)")
            }
            continue

        case .openSettings:
            await openSettingsMenu(
                composer: composer,
                activeModelConfig: &activeModelConfig,
                session: &session,
                activeTheme: &activeTheme,
                uiMode: &uiMode,
                useAdvancedUI: &useAdvancedUI,
                renderer: &renderer,
                viewport: &viewport,
                uiState: &uiState,
                supportsFramedUI: supportsFramedUI,
                capabilities: capabilities,
                streamState: &streamState,
                toolTimeline: &toolTimeline,
                streamingPreview: &streamingPreview,
                recentSessions: &recentSessions,
                selectedSessionChipIndex: &selectedSessionChipIndex
            )
            continue

        case .switchSession(let raw):
            guard !recentSessions.isEmpty else {
                printMuted("No saved sessions.")
                continue
            }
            let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if token == "next" || token == "n" {
                selectedSessionChipIndex = wrappedIndex(selectedSessionChipIndex + 1, count: recentSessions.count)
            } else if token == "prev" || token == "previous" || token == "p" {
                selectedSessionChipIndex = wrappedIndex(selectedSessionChipIndex - 1, count: recentSessions.count)
            } else if let idPrefix = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !idPrefix.isEmpty {
                if let idx = recentSessions.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                    selectedSessionChipIndex = idx
                } else {
                    printError("No session matching '\(idPrefix)'.")
                    continue
                }
            }
            let target = recentSessions[selectedSessionChipIndex]
            do {
                let loaded = try await SessionManager.shared.loadSession(id: target.id)
                session = loaded
                if let pinned = session.modelConfig { activeModelConfig = pinned }
                uiMode = session.uiMode
                useAdvancedUI = supportsFramedUI && uiMode == .framed
                activeTheme = TUITheme.named(session.activeThemeName) ?? activeTheme
                renderer?.setTheme(activeTheme)
                if useAdvancedUI, let viewport {
                    viewport.reset()
                    for msg in session.messages.suffix(10) {
                        let role = msg.role.lowercased() == "assistant" ? "assistant" : "you"
                        viewport.append(role: role, content: msg.content)
                    }
                    viewport.append(role: "system", content: "Quick-switched to session \(String(target.id.uuidString.prefix(8))).")
                }
                recentSessions = await SessionManager.shared.listSessions()
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: activeModelConfig.modeLabel,
                        modelConfig: activeModelConfig,
                        uiMode: uiMode,
                        streamState: streamState,
                        contextMeter: conversationContextMeter(session: session),
                        toolTimeline: toolTimeline,
                        streamingPreview: streamingPreview,
                        sessions: recentSessions,
                        selectedSessionChipIndex: selectedSessionChipIndex
                    )
                    uiState = state
                }
            } catch {
                printError("Session switch failed: \(error.localizedDescription)")
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
                        mode: activeModelConfig.modeLabel
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
                        mode: activeModelConfig.modeLabel
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
                    mode: activeModelConfig.modeLabel
                )
                uiState = state
            } else {
                print("\u{001B}[2J\u{001B}[H", terminator: "")
                fflush(stdout)
            }
            continue

        case .setTheme(let name):
            if renderer == nil, supportsFramedUI {
                renderer = introRenderer ?? TUIRenderer(theme: activeTheme, capabilities: capabilities)
            }
            if let selected = TUITheme.named(name) {
                activeTheme = selected
                renderer?.setTheme(selected)
                session.activeThemeName = selected.name
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "system", content: "Theme changed to '\(selected.name)'.")
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: activeModelConfig.modeLabel
                    )
                    uiState = state
                } else {
                    renderer?.clearScreen()
                    renderer?.renderBannerAnimated(
                        provider: activeModelConfig.provider.displayName,
                        model: activeModelConfig.model ?? activeModelConfig.modeLabel,
                        uiMode: uiMode.rawValue,
                        streamState: streamState
                    )
                    printSuccess("Theme changed to '\(selected.name)'.")
                }
                do {
                    try await SessionManager.shared.saveSession(session)
                } catch {
                    printWarning("Failed to persist theme: \(error.localizedDescription)")
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
                        mode: activeModelConfig.modeLabel
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
                mode: activeModelConfig.modeLabel
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

        var fullResponse = ""

        startSpinner(message: "Thinking", delayMs: uiConfig.spinnerDelayMs)
        streamState = "thinking"
        streamingPreview = ""
        toolTimeline.removeAll(keepingCapacity: true)

        do {
            let modelClient = try makeModelClient(config: activeModelConfig)
            let streamBuffer = StreamEventBuffer()
            fullResponse = try await withResponseTimeout(seconds: effectiveResponseTimeout(for: activeModelConfig, requestedSeconds: timeout)) {
                try await modelClient.respondStream(
                    prompt: modelPrompt,
                    tools: tools,
                    instructions: instructions,
                    onEvent: { event in
                        await streamBuffer.record(event)
                    }
                )
            }
            let streamSnapshot = await streamBuffer.snapshot()
            streamState = streamSnapshot.state
            streamingPreview = streamSnapshot.preview
            toolTimeline = streamSnapshot.timeline

            if includeAppleTools,
               let recovered = await resolveAppleRefusalFallback(
                   userPrompt: line,
                   modelReply: fullResponse,
                   modelClient: modelClient
               ) {
                fullResponse = recovered
            }

            if includeAppleTools,
               let recovered = await resolveNotesComposeFallback(
                   userPrompt: line,
                   modelReply: fullResponse,
                   modelClient: modelClient,
                   timeoutSeconds: timeout
               ) {
                fullResponse = recovered
            }

            if includeWebTools,
               let recovered = await resolveWebRefusalFallback(
                   userPrompt: line,
                   modelReply: fullResponse,
                   instructions: instructions,
                   timeoutSeconds: timeout,
                   modelClient: modelClient
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

            if let recovered = await resolveFileSaveIntentFallback(
                userPrompt: line,
                modelReply: fullResponse,
                session: session
            ) {
                fullResponse = recovered
            }

            let _ = stopSpinner()
            streamState = "idle"
            if useAdvancedUI, let renderer, var state = uiState, let viewport {
                viewport.append(role: "assistant", content: fullResponse)
                renderAdvancedShell(
                    renderer: renderer,
                    state: &state,
                    viewport: viewport,
                    cwd: session.workingDir,
                    mode: activeModelConfig.modeLabel,
                    modelConfig: activeModelConfig,
                    uiMode: uiMode,
                    streamState: streamState,
                    contextMeter: conversationContextMeter(session: session),
                    toolTimeline: toolTimeline,
                    streamingPreview: streamingPreview,
                    sessions: recentSessions,
                    selectedSessionChipIndex: selectedSessionChipIndex
                )
                uiState = state
            } else {
                // In interactive mode, always show full assistant output.
                printAssistantMessage(fullResponse, verbose: true)
            }
        } catch {
            let _ = stopSpinner()
            streamState = "error"
            let err = error.localizedDescription
            if activeModelConfig.provider == .ollama,
               err.localizedCaseInsensitiveContains("failed to parse JSON"),
               let recovered = await resolveOllamaWebPDFFallback(userPrompt: line) {
                fullResponse = recovered
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "assistant", content: fullResponse)
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: activeModelConfig.modeLabel,
                        modelConfig: activeModelConfig,
                        uiMode: uiMode,
                        streamState: "idle",
                        contextMeter: conversationContextMeter(session: session),
                        toolTimeline: toolTimeline,
                        streamingPreview: streamingPreview,
                        sessions: recentSessions,
                        selectedSessionChipIndex: selectedSessionChipIndex
                    )
                    uiState = state
                } else {
                    printAssistantMessage(fullResponse, verbose: true)
                }
                session.addMessage(role: "assistant", content: fullResponse)
                continue
            }
            if activeModelConfig.provider == .ollama,
               err.localizedCaseInsensitiveContains("failed to parse JSON"),
               let recovered = await resolveOllamaSaveFallback(userPrompt: line, session: session) {
                fullResponse = recovered
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "assistant", content: fullResponse)
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: activeModelConfig.modeLabel,
                        modelConfig: activeModelConfig,
                        uiMode: uiMode,
                        streamState: "idle",
                        contextMeter: conversationContextMeter(session: session),
                        toolTimeline: toolTimeline,
                        streamingPreview: streamingPreview,
                        sessions: recentSessions,
                        selectedSessionChipIndex: selectedSessionChipIndex
                    )
                    uiState = state
                } else {
                    printAssistantMessage(fullResponse, verbose: true)
                }
                session.addMessage(role: "assistant", content: fullResponse)
                continue
            }
            if activeModelConfig.provider == .ollama,
               let missingModel = extractMissingModelName(from: err) {
                if promptYesNo("Model '\(missingModel)' is missing. Pull now? [y/N] ") {
                    if runOllamaPull(model: missingModel) {
                        printSuccess("Pulled \(missingModel). Re-run your prompt.")
                    } else {
                        printError("Failed to pull \(missingModel).")
                    }
                } else {
                    printMuted("Install with: ollama pull \(missingModel)")
                }
                fullResponse = "Error: \(err)"
                continue
            }
            if includeAppleTools,
               isAppleIntentPrompt(line),
               (err.contains("Failed to deserialize a Generable type")
               || err.contains("The operation couldn’t be completed")) {
                let recoveryClient = try? makeModelClient(
                    config: activeModelConfig
                )
                if let recoveryClient,
                   let recovered = await resolveAppleIntentDirect(
                       userPrompt: line,
                       modelClient: recoveryClient
                   ) {
                fullResponse = recovered
                if useAdvancedUI, let renderer, var state = uiState, let viewport {
                    viewport.append(role: "assistant", content: fullResponse)
                    renderAdvancedShell(
                        renderer: renderer,
                        state: &state,
                        viewport: viewport,
                        cwd: session.workingDir,
                        mode: activeModelConfig.modeLabel
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
                            mode: activeModelConfig.modeLabel
                        )
                        uiState = state
                    } else {
                        printError("Error: \(error.localizedDescription)")
                    }
                    fullResponse = "Error: \(error.localizedDescription)"
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
                        mode: activeModelConfig.modeLabel
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
            recentSessions = await SessionManager.shared.listSessions()
        } catch {
            printWarning("Auto-save failed: \(error.localizedDescription)")
        }

        if !useAdvancedUI {
            print()
        }
    }

}

private func animatedPromptFrame() -> String {
    let t = Date().timeIntervalSinceReferenceDate
    let cursorStar = rotatingStarCursor(at: t)

    let cursorGradient = animatedGradientText(
        cursorStar,
        time: t,
        speed: 1.05,
        start: (120, 210, 255),
        end: (80, 255, 210),
        flashStrength: 0.22,
        bold: true
    )

    // Pulse the label brightness for a subtle "flash" effect.
    let label = animatedGradientText(
        "apple-code",
        time: t,
        speed: 0.85,
        start: (255, 95, 215),
        end: (120, 200, 255),
        flashStrength: 0.2,
        bold: true
    )

    let arrow = animatedGradientText(
        "›",
        time: t,
        speed: 1.6,
        start: (90, 220, 255),
        end: (30, 255, 200),
        flashStrength: 0.1,
        bold: true
    )
    let glyph = "\(cursorGradient)\(TUI.reset)"
    return "\(glyph) \(label) \(arrow) "
}

private func rotatingStarCursor(at time: TimeInterval) -> String {
    let frames = ["✦", "✧", "✶", "✷", "✹", "✺", "✹", "✷", "✶", "✧"]
    let frameIndex = Int(time * 5.0) % frames.count
    let haloPulse = 0.5 + 0.5 * sin(time * 2.0)
    let halo = haloPulse > 0.62 ? "·" : " "
    return "\(halo)\(frames[frameIndex])\(halo)"
}

private func animatedGradientText(
    _ text: String,
    time: TimeInterval,
    speed: Double,
    start: (Int, Int, Int),
    end: (Int, Int, Int),
    flashStrength: Double,
    bold: Bool
) -> String {
    let chars = Array(text)
    guard !chars.isEmpty else { return text }

    let pulse = 0.5 + 0.5 * sin(time * speed * 1.7)
    let brightness = 1.0 + flashStrength * pulse

    var out = ""
    for (index, char) in chars.enumerated() {
        let count = max(1, chars.count - 1)
        let position = (Double(index) / Double(count)) + (time * speed * 0.33)
        let wave = 0.5 + 0.5 * sin(position * Double.pi * 2.0)
        let r = boostedChannel(mixChannel(start.0, end.0, t: wave), brightness: brightness)
        let g = boostedChannel(mixChannel(start.1, end.1, t: wave), brightness: brightness)
        let b = boostedChannel(mixChannel(start.2, end.2, t: wave), brightness: brightness)
        out += "\(ansiTrueColor(r: r, g: g, b: b, bold: bold))\(char)"
    }
    out += TUI.reset
    return out
}

private func mixChannel(_ a: Int, _ b: Int, t: Double) -> Int {
    Int(Double(a) + (Double(b - a) * min(max(t, 0.0), 1.0)))
}

private func boostedChannel(_ value: Int, brightness: Double) -> Int {
    let scaled = Int(Double(value) * brightness)
    return min(255, max(0, scaled))
}

private func ansiTrueColor(r: Int, g: Int, b: Int, bold: Bool) -> String {
    let color = "\u{001B}[38;2;\(r);\(g);\(b)m"
    return bold ? "\(TUI.bold)\(color)" : color
}

private func renderAdvancedShell(
    renderer: TUIRenderer,
    state: inout UIState,
    viewport: ConversationViewport,
    cwd: String,
    mode: String,
    modelConfig: ModelConfig = .appleDefault,
    uiMode: UIMode = .classic,
    streamState: String = "idle",
    contextMeter: String = "",
    toolTimeline: [String] = [],
    streamingPreview: String = "",
    sessions: [SessionSummary] = [],
    selectedSessionChipIndex: Int = 0
) {
    let size = renderer.terminalSize()
    state.width = size.width
    state.height = size.height

    let innerWidth = max(20, state.width - 4)
    let contentRows = max(3, state.contentHeight - 2)
    let border = renderer.theme.border

    // Full-frame redraw keeps layout deterministic after resize and long outputs.
    renderer.clearScreen()
    renderer.renderBannerAnimated(
        provider: modelConfig.provider.displayName,
        model: modelConfig.model ?? mode,
        uiMode: uiMode.rawValue,
        streamState: streamState
    )
    state.bannerHeight = renderer.lastBannerHeight

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

    let statusLeft = "[\(mode)] [\(truncateMiddle(cwd, maxChars: max(12, innerWidth / 3)))]"
    let scroll = viewport.scrollState(width: innerWidth, maxLines: contentRows)
    let scrollPart = scroll.maxOffset > 0 ? "Fn+↑/↓ \(scroll.offset)/\(scroll.maxOffset)" : "Fn+↑/↓"
    let statusRight = "Enter submit • ↑/↓ edit • \(scrollPart) • /settings • /quit"
    let divider = "  "
    var status = "\(statusLeft)\(divider)\(statusRight)"
    if status.count > innerWidth {
        status = String(status.prefix(max(8, innerWidth - 1))) + "…"
    }
    let contextChip = contextMeter.isEmpty ? "" : "  \(contextMeter)"
    var statusLine2 = "stream \(streamState)\(contextChip)"
    if !toolTimeline.isEmpty {
        statusLine2 += "  •  " + toolTimeline.suffix(2).joined(separator: "  |  ")
    }
    if statusLine2.count > innerWidth {
        statusLine2 = String(statusLine2.prefix(max(8, innerWidth - 1))) + "…"
    }
    let status2Pad = max(0, innerWidth - statusLine2.count)

    let sessionLine = sessionChipLine(
        sessions: sessions,
        selectedIndex: selectedSessionChipIndex,
        maxWidth: innerWidth
    )
    let sessionPad = max(0, innerWidth - sessionLine.count)

    // Persistent footer pinned to the last three terminal rows.
    let topRow = max(1, state.height - 2)
    let middleRow = max(1, state.height - 1)
    let bottomRow = max(1, state.height)
    print("\u{001B}[\(topRow);1H", terminator: "")
    print("\u{001B}[2K\(renderer.theme.primary)╭\(String(repeating: "─", count: innerWidth + 2))╮\(TUI.reset)", terminator: "")
    print("\u{001B}[\(middleRow);1H", terminator: "")
    print("\u{001B}[2K\(renderer.theme.primary)│\(TUI.reset)\(TUI.dim)\(sessionLine)\(TUI.reset)\(String(repeating: " ", count: sessionPad))\(renderer.theme.primary)│\(TUI.reset)", terminator: "")
    print("\u{001B}[\(bottomRow);1H", terminator: "")
    let pulseColor = pulseBorderColor(state: streamState)
    let streamPreviewSuffix = streamingPreview.isEmpty ? "" : "  •  " + truncateSingleLine(streamingPreview, maxChars: max(10, innerWidth / 3))
    var mergedStatus = status + streamPreviewSuffix
    if mergedStatus.count > innerWidth {
        mergedStatus = String(mergedStatus.prefix(max(8, innerWidth - 1))) + "…"
    }
    let mergedPad = max(0, innerWidth - mergedStatus.count)
    print("\u{001B}[2K\(pulseColor)│\(TUI.reset)\(TUI.dim)\(mergedStatus)\(TUI.reset)\(String(repeating: " ", count: mergedPad))\(pulseColor)│\(TUI.reset)", terminator: "")
    print("\u{001B}[\(max(1, state.height - 3));1H", terminator: "")
    print("\u{001B}[2K\(renderer.theme.primary)│\(TUI.reset)\(TUI.dim)\(statusLine2)\(TUI.reset)\(String(repeating: " ", count: status2Pad))\(renderer.theme.primary)│\(TUI.reset)", terminator: "")

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
        return "\(TUI.Colors.brightCyan)\(TUI.bold)you:\(TUI.reset) " + styleDiffLine(String(line.dropFirst(5)))
    }
    if line.hasPrefix("assistant: ") {
        return "\(TUI.Colors.brightBlue)\(TUI.bold)assistant:\(TUI.reset) " + styleDiffLine(String(line.dropFirst(11)))
    }
    if line.hasPrefix("system: ") {
        return "\(TUI.Colors.brightMagenta)\(TUI.bold)system:\(TUI.reset) " + styleDiffLine(String(line.dropFirst(8)))
    }
    if line.hasPrefix("error: ") {
        return "\(TUI.errorColor)\(TUI.bold)error:\(TUI.reset) " + styleDiffLine(String(line.dropFirst(7)))
    }
    return styleDiffLine(line)
}

private func styleDiffLine(_ line: String) -> String {
    if line.hasPrefix("@@") {
        return "\(TUI.Colors.brightYellow)\(line)\(TUI.reset)"
    }
    if line.hasPrefix("+++") || line.hasPrefix("---") {
        return "\(TUI.Colors.brightMagenta)\(line)\(TUI.reset)"
    }
    if line.hasPrefix("+"), !line.hasPrefix("+++"){
        return "\(TUI.Colors.brightGreen)\(line)\(TUI.reset)"
    }
    if line.hasPrefix("-"), !line.hasPrefix("---") {
        return "\(TUI.Colors.brightRed)\(line)\(TUI.reset)"
    }
    return line
}

private func pulseBorderColor(state: String) -> String {
    switch state {
    case "thinking":
        return TUI.Colors.brightBlue
    case "streaming":
        return TUI.Colors.brightCyan
    case "tool":
        return TUI.Colors.brightYellow
    case "done", "idle":
        return TUI.Colors.brightGreen
    case "error":
        return TUI.Colors.brightRed
    default:
        return TUI.Colors.brightCyan
    }
}

private func sessionChipLine(sessions: [SessionSummary], selectedIndex: Int, maxWidth: Int) -> String {
    guard !sessions.isEmpty else {
        return "sessions: none"
    }
    let slice = Array(sessions.prefix(5))
    var parts: [String] = ["sessions"]
    for (index, session) in slice.enumerated() {
        let id = String(session.id.uuidString.prefix(6))
        let label = index == selectedIndex ? "[\(id)]" : id
        parts.append(label)
    }
    var text = parts.joined(separator: "  ")
    if text.count > maxWidth {
        text = String(text.prefix(max(8, maxWidth - 1))) + "…"
    }
    return text
}

private func wrappedIndex(_ value: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let n = value % count
    return n >= 0 ? n : n + count
}

private func conversationContextMeter(session: Session) -> String {
    let approxTokens = max(1, session.messages.reduce(0) { $0 + ($1.content.count / 4) })
    let budget = 4096
    let ratio = min(1.0, Double(approxTokens) / Double(budget))
    let blocks = 10
    let filled = min(blocks, Int((ratio * Double(blocks)).rounded(.awayFromZero)))
    let bar = String(repeating: "■", count: filled) + String(repeating: "□", count: max(0, blocks - filled))
    return "ctx \(bar) \(approxTokens)/\(budget)"
}

private func openSettingsMenu(
    composer: InputComposer?,
    activeModelConfig: inout ModelConfig,
    session: inout Session,
    activeTheme: inout TUITheme,
    uiMode: inout UIMode,
    useAdvancedUI: inout Bool,
    renderer: inout TUIRenderer?,
    viewport: inout ConversationViewport?,
    uiState: inout UIState?,
    supportsFramedUI: Bool,
    capabilities: TerminalCapabilities,
    streamState: inout String,
    toolTimeline: inout [String],
    streamingPreview: inout String,
    recentSessions: inout [SessionSummary],
    selectedSessionChipIndex: inout Int
) async {
    let options = [
        "Switch Provider",
        "Select Ollama Model",
        "Pull Recommended Qwen Model",
        "Toggle UI Mode",
        "Select Theme",
        "Switch Session",
        "Show Model Status",
        "Close",
    ]

    let selectedIndex: Int?
    if let composer {
        selectedIndex = composer.readMenuSelection(title: "Settings", options: options)
    } else {
        print("\nSettings")
        for (idx, option) in options.enumerated() {
            print("  \(idx + 1). \(option)")
        }
        print("\(TUI.promptColor)Selection>\(TUI.reset) ", terminator: "")
        fflush(stdout)
        if let raw = readLine(strippingNewline: true),
           let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           value > 0, value <= options.count {
            selectedIndex = value - 1
        } else {
            selectedIndex = nil
        }
    }

    guard let selectedIndex else { return }
    switch selectedIndex {
    case 0:
        if activeModelConfig.provider == .apple {
            let envBase = ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = (envBase?.isEmpty == false) ? (envBase ?? "http://127.0.0.1:11434") : "http://127.0.0.1:11434"
            let normalized = try? ModelConfig.normalizeBaseURL(baseURL)
            let installed = await OllamaModelDiscovery.installedModels(baseURL: normalized ?? URL(string: "http://127.0.0.1:11434")!)
            if let preferred = OllamaModelDiscovery.preferredDefaultModel(from: installed) {
                activeModelConfig = ModelConfig(provider: .ollama, model: preferred, baseURL: normalized?.absoluteString ?? baseURL)
                session.modelConfig = activeModelConfig
            } else {
                if promptYesNo("No local Ollama models found. Pull qwen3.5:4b now? [y/N] ") {
                    if runOllamaPull(model: "qwen3.5:4b") {
                        activeModelConfig = ModelConfig(provider: .ollama, model: "qwen3.5:4b", baseURL: normalized?.absoluteString ?? baseURL)
                        session.modelConfig = activeModelConfig
                    }
                }
            }
        } else {
            activeModelConfig = .appleDefault
            session.modelConfig = activeModelConfig
        }
    case 1:
        let rawBaseURL = activeModelConfig.baseURL ?? ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"] ?? "http://127.0.0.1:11434"
        guard let baseURL = URL(string: rawBaseURL) else { break }
        let installed = await OllamaModelDiscovery.installedModels(baseURL: baseURL)
        let combined = Array(Set(installed + OllamaModelDiscovery.recommendedQwenModels)).sorted()
        guard !combined.isEmpty else { break }
        let modelIdx = readMenuSelection(composer: composer, title: "Select Ollama Model", options: combined)
        if let modelIdx, combined.indices.contains(modelIdx) {
            activeModelConfig = ModelConfig(provider: .ollama, model: combined[modelIdx], baseURL: rawBaseURL)
            session.modelConfig = activeModelConfig
        }
    case 2:
        let pullOptions = OllamaModelDiscovery.recommendedQwenModels
        let idx = readMenuSelection(composer: composer, title: "Pull Qwen Model", options: pullOptions)
        if let idx, pullOptions.indices.contains(idx) {
            _ = runOllamaPull(model: pullOptions[idx])
        }
    case 3:
        let nextMode: UIMode = uiMode == .framed ? .classic : .framed
        if nextMode == .framed && !supportsFramedUI {
            printError("Framed UI requires a Unicode-capable interactive terminal.")
            break
        }
        uiMode = nextMode
        session.uiMode = nextMode
        useAdvancedUI = supportsFramedUI && nextMode == .framed
        if useAdvancedUI, renderer == nil {
            renderer = TUIRenderer(theme: activeTheme, capabilities: capabilities)
        }
    case 4:
        let themes = TUITheme.all.map(\.name)
        let idx = readMenuSelection(composer: composer, title: "Select Theme", options: themes)
        if let idx, themes.indices.contains(idx), let selected = TUITheme.named(themes[idx]) {
            activeTheme = selected
            session.activeThemeName = selected.name
            renderer?.setTheme(selected)
        }
    case 5:
        guard !recentSessions.isEmpty else { break }
        selectedSessionChipIndex = wrappedIndex(selectedSessionChipIndex + 1, count: recentSessions.count)
    case 6:
        do {
            let client = try makeModelClient(config: activeModelConfig)
            print("\n" + client.statusLines().joined(separator: "\n"))
        } catch {
            printError(error.localizedDescription)
        }
    default:
        break
    }

    do {
        try await SessionManager.shared.saveSession(session)
        recentSessions = await SessionManager.shared.listSessions()
    } catch {
        printWarning("Failed to persist settings changes: \(error.localizedDescription)")
    }
    streamState = "idle"
    toolTimeline.removeAll(keepingCapacity: true)
    streamingPreview = ""
}

private func promptYesNo(_ prompt: String) -> Bool {
    print(prompt, terminator: "")
    fflush(stdout)
    guard let raw = readLine(strippingNewline: true)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() else {
        return false
    }
    return raw == "y" || raw == "yes"
}

private func readMenuSelection(
    composer: InputComposer?,
    title: String,
    options: [String]
) -> Int? {
    if let composer {
        return composer.readMenuSelection(title: title, options: options)
    }
    guard !options.isEmpty else { return nil }
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

private func runOllamaPull(model: String) -> Bool {
    printMuted("Running: ollama pull \(model)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["ollama", "pull", model]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        printError("Failed to run ollama pull: \(error.localizedDescription)")
        return false
    }
}

private func extractMissingModelName(from message: String) -> String? {
    let marker = "Model '"
    guard let start = message.range(of: marker)?.upperBound else { return nil }
    guard let end = message[start...].firstIndex(of: "'") else { return nil }
    let model = String(message[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    return model.isEmpty ? nil : model
}

private func effectiveResponseTimeout(for config: ModelConfig, requestedSeconds: Int) -> Int {
    let requested = max(5, requestedSeconds)
    switch config.provider {
    case .apple:
        return requested
    case .ollama:
        // Local Ollama models (especially larger ones) can legitimately take longer.
        return max(300, requested)
    }
}

private func resolveOllamaSaveFallback(userPrompt: String, session: Session) async -> String? {
    let lower = userPrompt.lowercased()
    guard lower.contains("save") || lower.contains("write") else { return nil }
    guard lower.contains("file") || lower.contains(".md") || lower.contains(".txt") else { return nil }

    guard let source = session.messages.reversed().first(where: {
        $0.role.lowercased() == "assistant"
            && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !$0.content.lowercased().hasPrefix("error:")
    })?.content else {
        return nil
    }

    let path = detectFilename(in: userPrompt) ?? "output.md"
    do {
        let result = try await WriteFileTool().call(arguments: .init(path: path, content: source))
        return "Saved previous assistant output to \(path).\n\(result)"
    } catch {
        return "Could not save to \(path): \(error.localizedDescription)"
    }
}

private func detectFilename(in text: String) -> String? {
    let pattern = #"(?:^|\s)([A-Za-z0-9_./-]+\.(?:md|txt|swift|json|yaml|yml|js|ts|py|html|css))(?:\s|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return nil
    }
    let range = NSRange(location: 0, length: text.utf16.count)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let filenameRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    let filename = String(text[filenameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    return filename.isEmpty ? nil : filename
}

private func resolveFileSaveIntentFallback(
    userPrompt: String,
    modelReply: String,
    session: Session
) async -> String? {
    guard isFileSaveIntentPrompt(userPrompt) else { return nil }

    let path = inferTargetSavePath(userPrompt: userPrompt, session: session) ?? "output.md"
    let absolutePath = (path as NSString).isAbsolutePath
        ? path
        : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)

    // If file already exists, trust successful write path and avoid unnecessary overwrite.
    if FileManager.default.fileExists(atPath: absolutePath) {
        return nil
    }

    guard let source = sourceContentForFileSave(from: session, modelReply: modelReply) else {
        return nil
    }

    do {
        let result = try await WriteFileTool().call(arguments: .init(path: path, content: source))
        return "Saved content to \(path).\n\(result)"
    } catch {
        return "Could not save to \(path): \(error.localizedDescription)"
    }
}

private func isFileSaveIntentPrompt(_ prompt: String) -> Bool {
    let lower = prompt.lowercased()
    let saveSignal = lower.contains("save")
        || lower.contains("write")
        || lower.contains("create")
    let fileSignal = lower.contains("file")
        || lower.contains("folder")
        || lower.contains(".py")
        || lower.contains(".swift")
        || lower.contains(".md")
        || lower.contains(".txt")
        || lower.contains("server.py")
    return saveSignal && fileSignal
}

private func inferTargetSavePath(userPrompt: String, session: Session) -> String? {
    if let explicit = detectFilename(in: userPrompt) {
        return explicit
    }

    for message in session.messages.reversed() {
        let role = message.role.lowercased()
        guard role == "user" || role == "assistant" else { continue }
        if let inferred = detectFilename(in: message.content) {
            return inferred
        }
    }
    return nil
}

private func sourceContentForFileSave(from session: Session, modelReply: String) -> String? {
    if let fenced = extractFirstFencedCodeBlock(from: modelReply), !fenced.isEmpty {
        return fenced
    }

    if let priorAssistant = session.messages.reversed().first(where: { $0.role.lowercased() == "assistant" })?.content {
        if let fenced = extractFirstFencedCodeBlock(from: priorAssistant), !fenced.isEmpty {
            return fenced
        }
        let trimmed = priorAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.lowercased().hasPrefix("error:") {
            return trimmed
        }
    }

    let trimmedReply = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedReply.isEmpty && !trimmedReply.lowercased().hasPrefix("error:") {
        return trimmedReply
    }
    return nil
}

private func extractFirstFencedCodeBlock(from text: String) -> String? {
    guard let startRange = text.range(of: "```") else { return nil }
    let afterFence = startRange.upperBound
    guard let endRange = text.range(of: "```", range: afterFence..<text.endIndex) else { return nil }

    var block = String(text[afterFence..<endRange.lowerBound])
    if let newline = block.firstIndex(of: "\n") {
        let firstLine = block[..<newline]
        let maybeLanguage = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !maybeLanguage.isEmpty && maybeLanguage.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            block = String(block[block.index(after: newline)...])
        }
    }
    let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func resolveOllamaWebPDFFallback(userPrompt: String) async -> String? {
    let lower = userPrompt.lowercased()
    let hasWebIntent = lower.contains("search the web")
        || lower.contains("web search")
        || lower.contains("latest news")
    let hasPDFIntent = lower.contains("pdf")
        && (lower.contains("brief") || lower.contains("report") || lower.contains("document") || lower.contains("generate"))
    guard hasWebIntent && hasPDFIntent else { return nil }

    let query = extractWebQuery(from: userPrompt) ?? userPrompt
    let pdfPath = detectFilename(in: userPrompt) ?? "briefing.pdf"
    let title = "Briefing: \(query)"

    do {
        let searchRaw = try await WebSearchTool().call(arguments: .init(query: query, limit: 8))
        let briefBody = """
        Research query:
        \(query)

        Findings:
        \(searchRaw)

        Generated by apple-code fallback due Ollama tool JSON parser error.
        """

        let pdfResult = try await CreatePDFTool().call(arguments: .init(path: pdfPath, title: title, content: briefBody))
        return """
        Ollama tool-call parser error occurred, so I ran a direct fallback workflow.
        Created briefing PDF at \(pdfPath).

        \(pdfResult)
        """
    } catch {
        return "Fallback web->PDF flow failed: \(error.localizedDescription)"
    }
}

private func extractWebQuery(from prompt: String) -> String? {
    let lower = prompt.lowercased()
    let markers = [
        "search the web for",
        "web search for",
        "search for",
    ]

    for marker in markers {
        if let range = lower.range(of: marker) {
            let start = range.upperBound
            var query = String(prompt[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let stop = query.lowercased().range(of: "and then") {
                query = String(query[..<stop.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            query = query.trimmingCharacters(in: CharacterSet(charactersIn: ",. "))
            if !query.isEmpty {
                return query
            }
        }
    }
    return nil
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
    /settings        Open settings menu (provider/model/ui/theme/session)
    /ui [mode]       Set UI mode (classic, framed)
    /session ...     Session quick switch (next, prev, id-prefix)
    /cd <path>       Change working directory
    /clear (/c)      Redraw the screen
    /theme <name>    Set theme (\(TUITheme.all.map { $0.name }.joined(separator: ", ")))
    /help (/h)       Show this help
    /quit (/q)       Exit and save

    Navigation:
    Fn+↑ / Fn+↓      Scroll chat viewport
    Ctrl+Y / Ctrl+V  Scroll chat viewport (fallback)
    Ctrl+P           Open settings
    Esc(Ctrl+[)/Ctrl+]  Switch selected session chip
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
