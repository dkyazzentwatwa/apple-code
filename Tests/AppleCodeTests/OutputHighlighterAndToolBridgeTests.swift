import XCTest
import FoundationModels
@testable import apple_code

final class OutputHighlighterAndToolBridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OutputHighlighter.cachedExternal = nil
        OutputHighlighter.checkedExternal = true
    }

    func testOutputHighlighterRenderNonTTYReturnsOriginal() {
        let text = "plain"
        XCTAssertEqual(OutputHighlighter.render(text, isTTY: false), text)
    }

    func testOutputHighlighterRendersFencedCodeWithFallbackHighlighter() {
        let message = """
        before
        ```swift
        let x = 42
        // comment
        ```
        after
        """
        let rendered = OutputHighlighter.render(message, isTTY: true)
        XCTAssertTrue(rendered.contains("```swift"))
        XCTAssertTrue(rendered.contains("42"))
        XCTAssertTrue(rendered.contains("before"))
        XCTAssertTrue(rendered.contains("after"))
    }

    func testOutputHighlighterCoversMultipleLanguagePaths() {
        OutputHighlighter.checkedExternal = true
        OutputHighlighter.cachedExternal = nil

        let message = """
        ```python
        # comment
        value = 123
        print("x")
        ```
        ```bash
        #!/bin/bash
        echo 42
        ```
        ```json
        {"ok": true, "n": 5}
        ```
        """
        let rendered = OutputHighlighter.render(message, isTTY: true)
        XCTAssertTrue(rendered.contains("```python"))
        XCTAssertTrue(rendered.contains("```bash"))
        XCTAssertTrue(rendered.contains("```json"))
        XCTAssertTrue(rendered.contains("123"))
        XCTAssertTrue(rendered.contains("42"))
        XCTAssertTrue(rendered.contains("true"))
    }

    func testOutputHighlighterExternalDetectionPathExecutes() {
        OutputHighlighter.checkedExternal = false
        OutputHighlighter.cachedExternal = nil
        let _ = OutputHighlighter.render("```swift\nlet x = 1\n```", isTTY: true)
        XCTAssertTrue(OutputHighlighter.checkedExternal)
    }

    func testOutputHighlighterHandlesUnclosedFence() {
        let message = "```python\nprint('hi')"
        let rendered = OutputHighlighter.render(message, isTTY: true)
        XCTAssertTrue(rendered.contains("```python"))
        XCTAssertTrue(rendered.contains("print"))
    }

    func testToolBridgeDefinitionsAndInvokeErrors() async {
        let allTools: [any Tool] = [
            ReadFileTool(), WriteFileTool(), ListDirectoryTool(), SearchFilesTool(), SearchContentTool(),
            RunCommandTool(), CreatePDFTool(), WebSearchTool(), WebFetchTool(), AgentBrowserTool(),
            NotesTool(), MailTool(), CalendarTool(), RemindersTool(), MessagesTool(),
        ]

        let defs = ToolBridge.toolDefinitions(for: allTools)
        XCTAssertEqual(defs.count, allTools.count)

        let unavailable = await ToolBridge.invoke(toolName: "doesNotExist", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(unavailable.contains("is not available"))

        let invalidJSON = await ToolBridge.invoke(toolName: "readFile", argumentsJSON: "{", availableTools: allTools)
        XCTAssertTrue(invalidJSON.contains("Error invoking tool 'readFile'"))

        let wrongType = await ToolBridge.invoke(toolName: "readFile", argumentsJSON: "[]", availableTools: allTools)
        XCTAssertTrue(wrongType.contains("must be a JSON object"))

        let missingField = await ToolBridge.invoke(toolName: "readFile", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(missingField.contains("Missing required tool argument: path"))

        // Exercise additional argument coercion and case branches without external dependencies.
        let listDir = await ToolBridge.invoke(
            toolName: "listDirectory",
            argumentsJSON: #"{"recursive":"true"}"#,
            availableTools: allTools
        )
        XCTAssertFalse(listDir.isEmpty)

        let runCommand = await ToolBridge.invoke(
            toolName: "runCommand",
            argumentsJSON: #"{"command":"echo bridge","timeout":"2"}"#,
            availableTools: allTools
        )
        XCTAssertTrue(runCommand.contains("bridge"))

        let writeMissing = await ToolBridge.invoke(toolName: "writeFile", argumentsJSON: #"{"path":"x"}"#, availableTools: allTools)
        XCTAssertTrue(writeMissing.contains("Missing required tool argument: content"))
        let searchFilesMissing = await ToolBridge.invoke(toolName: "searchFiles", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(searchFilesMissing.contains("Missing required tool argument: pattern"))
        let searchContentMissing = await ToolBridge.invoke(toolName: "searchContent", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(searchContentMissing.contains("Missing required tool argument: pattern"))
        let createPdfMissing = await ToolBridge.invoke(toolName: "createPDF", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(createPdfMissing.contains("Missing required tool argument: path"))
        let webSearchMissing = await ToolBridge.invoke(toolName: "webSearch", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(webSearchMissing.contains("Missing required tool argument: query"))
        let webFetchMissing = await ToolBridge.invoke(toolName: "webFetch", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(webFetchMissing.contains("Missing required tool argument: url"))
        let agentMissing = await ToolBridge.invoke(toolName: "agentBrowser", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(agentMissing.contains("Missing required tool argument: action"))
        let notesMissing = await ToolBridge.invoke(toolName: "notes", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(notesMissing.contains("Missing required tool argument: action"))
        let mailMissing = await ToolBridge.invoke(toolName: "mail", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(mailMissing.contains("Missing required tool argument: action"))
        let calMissing = await ToolBridge.invoke(toolName: "calendar", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(calMissing.contains("Missing required tool argument: action"))
        let remMissing = await ToolBridge.invoke(toolName: "reminders", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(remMissing.contains("Missing required tool argument: action"))
        let msgMissing = await ToolBridge.invoke(toolName: "messages", argumentsJSON: "{}", availableTools: allTools)
        XCTAssertTrue(msgMissing.contains("Missing required tool argument: action"))
    }
}
