import Foundation
import FoundationModels

func runInteractiveREPL(
    session: inout Session,
    systemInstructions: String?,
    timeout: Int,
    includeAppleTools: Bool,
    includeWebTools: Bool,
    includeBrowserTools: Bool
) async -> Never {
    let capabilities = TerminalCapabilities.detect()
    let useAdvancedUI = capabilities.supportsAdvancedUI && capabilities.supportsUnicode
    var activeTheme = TUITheme.wow
    let renderer = useAdvancedUI ? TUIRenderer(theme: activeTheme, capabilities: capabilities) : nil
    let composer = useAdvancedUI ? InputComposer() : nil

    if let renderer {
        renderer.clearScreen()
        renderer.renderBannerAnimated()
    } else {
        printBanner()
    }

    var defaultPreamble = """
    You are apple-code, a local AI coding assistant. Be concise.
    Working directory: \(session.workingDir)
    Only use tools when the user asks. For greetings or chat, just respond with text.
    Never create, send, or modify anything unless explicitly asked.
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
    let instructions = systemInstructions.map { "\(defaultPreamble)\n\($0)" } ?? defaultPreamble

    if !session.messages.isEmpty {
        printMuted("Resuming session with \(session.messages.count) messages\n")
    }

    var shouldContinue = true

    while shouldContinue {
        let line: String
        if let renderer, let composer {
            guard let submitted = composer.readSubmission(renderer: renderer, cwd: session.workingDir), !submitted.isEmpty else {
                continue
            }
            line = submitted
            composer.addHistory(line)
            print()
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

        let command = parseCommand(line)

        switch command {
        case .quit:
            shouldContinue = false
            printMuted("\nSaving session...")
            do {
                try await SessionManager.shared.saveSession(session)
                printSuccess("Session saved.")
            } catch {
                printError("Failed to save session: \(error.localizedDescription)")
            }
            printMuted("\nGoodbye!")
            exit(0)

        case .newSession:
            do {
                try await SessionManager.shared.saveSession(session)
            } catch {
                printError("Failed to save session: \(error.localizedDescription)")
            }
            session = await SessionManager.shared.createSession(workingDir: session.workingDir)
            printSuccess("Started new session.")
            print()
            if let renderer {
                renderer.clearScreen()
                renderer.renderBannerAnimated()
            } else {
                printBanner()
            }

        case .listSessions:
            await handleSessionList()
            continue

        case .resumeSession(let id):
            if let loaded = await handleResumeSession(id: id) {
                session = loaded
            }
            continue

        case .deleteSession(let id):
            await handleDeleteSession(id: id)
            continue

        case .showHelp:
            printHelp()
            continue

        case .showModel:
            let model = SystemLanguageModel.default
            print("Model: \(model.availability)")
            if model.availability == .available {
                if #available(macOS 26.2, *) {
                    print("Supports streaming: yes")
                }
            }
            continue

        case .changeDirectory(let path):
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                FileManager.default.changeCurrentDirectoryPath(expandedPath)
                session.workingDir = expandedPath
                printSuccess("Changed directory to: \(expandedPath)")
            } else {
                printError("Directory not found: \(expandedPath)")
            }
            continue

        case .clear:
            if let renderer {
                renderer.clearScreen()
                renderer.renderBannerAnimated()
            } else {
                print("\u{001B}[2J\u{001B}[H")
                printBanner()
            }
            continue

        case .setTheme(let name):
            if renderer == nil {
                printMuted("Theme switching requires interactive TTY advanced mode.")
                continue
            }
            if let selected = TUITheme.named(name) {
                activeTheme = selected
                renderer?.setTheme(selected)
                renderer?.clearScreen()
                renderer?.renderBannerAnimated()
                printSuccess("Theme changed to '\(selected.name)'.")
            } else {
                let names = TUITheme.all.map { $0.name }.joined(separator: ", ")
                printMuted("Current theme: \(activeTheme.name). Available: \(names)")
            }
            continue

        case .none:
            break
        }

        printUserMessage(line)
        print()

        session.addMessage(role: "user", content: line)

        let tools = routeTools(
            for: line,
            includeAppleTools: includeAppleTools,
            includeWebTools: includeWebTools,
            includeBrowserTools: includeBrowserTools
        )

        let llmSession = LanguageModelSession(tools: tools, instructions: instructions)

        var fullResponse = ""

        startSpinner(message: "Thinking")

        do {
            fullResponse = try await withResponseTimeout(seconds: timeout) {
                let response = try await llmSession.respond(to: line)
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

            stopSpinner()
            printAssistantMessage(fullResponse)
        } catch {
            stopSpinner()
            let err = error.localizedDescription
            if includeAppleTools,
               isAppleIntentPrompt(line),
               (err.contains("Failed to deserialize a Generable type")
                || err.contains("The operation couldn’t be completed")),
               let recovered = await resolveAppleIntentDirect(userPrompt: line) {
                fullResponse = recovered
                printAssistantMessage(fullResponse)
            } else {
                printError("Error: \(error.localizedDescription)")
                fullResponse = "Error: \(error.localizedDescription)"
            }
        }

        session.addMessage(role: "assistant", content: fullResponse)

        do {
            try await SessionManager.shared.saveSession(session)
        } catch {
            printWarning("Auto-save failed: \(error.localizedDescription)")
        }

        print()
    }

    exit(0)
}
