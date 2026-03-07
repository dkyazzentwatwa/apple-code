import Foundation
import FoundationModels

protocol ModelClient: Sendable {
    var config: ModelConfig { get }
    func respond(
        prompt: String,
        tools: [any Tool],
        instructions: String
    ) async throws -> String
    func respondStream(
        prompt: String,
        tools: [any Tool],
        instructions: String,
        onEvent: @escaping (ModelEvent) async -> Void
    ) async throws -> String
    func statusLines() -> [String]
}

enum ModelEvent: Sendable {
    case status(String)
    case token(String)
    case toolCall(name: String)
    case toolResult(name: String, outputPreview: String)
    case completed(String)
}

extension ModelClient {
    func respondStream(
        prompt: String,
        tools: [any Tool],
        instructions: String,
        onEvent: @escaping (ModelEvent) async -> Void
    ) async throws -> String {
        await onEvent(.status("thinking"))
        let full = try await respond(prompt: prompt, tools: tools, instructions: instructions)
        for chunk in streamingChunks(from: full) {
            await onEvent(.token(chunk))
        }
        await onEvent(.completed(full))
        return full
    }

    fileprivate func streamingChunks(from text: String) -> [String] {
        if text.isEmpty { return [] }
        var chunks: [String] = []
        var lineBuffer = ""
        for character in text {
            lineBuffer.append(character)
            if character == "\n" || lineBuffer.count >= 18 {
                chunks.append(lineBuffer)
                lineBuffer = ""
            }
        }
        if !lineBuffer.isEmpty {
            chunks.append(lineBuffer)
        }
        return chunks
    }
}

func makeModelClient(
    config: ModelConfig,
    env: [String: String] = ProcessInfo.processInfo.environment
) throws -> any ModelClient {
    switch config.provider {
    case .apple:
        guard SystemLanguageModel.default.availability == .available else {
            throw ModelClientFactoryError.appleUnavailable
        }
        return AppleModelClient(config: config)

    case .ollama:
        guard let model = config.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
            throw ModelConfigError.missingModel
        }

        let rawBaseURL: String = config.baseURL
            ?? env["OLLAMA_BASE_URL"]
            ?? "http://127.0.0.1:11434"
        guard let baseURL = URL(string: rawBaseURL) else {
            throw ModelClientFactoryError.invalidBaseURL
        }
        return OllamaModelClient(config: config, model: model, baseURL: baseURL)
    }
}

enum ModelClientFactoryError: LocalizedError {
    case appleUnavailable
    case invalidBaseURL
    case modelNotInstalled(model: String)
    case ollamaUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .appleUnavailable:
            return "Apple Foundation Models not available. Requires macOS 26+ on Apple Silicon."
        case .invalidBaseURL:
            return "Ollama base URL is invalid."
        case .modelNotInstalled(let model):
            return "Model '\(model)' is not installed locally. Run: ollama pull \(model)"
        case .ollamaUnavailable(let detail):
            return "Ollama is unavailable: \(detail)"
        }
    }
}

private struct AppleModelClient: ModelClient {
    let config: ModelConfig

    func respond(
        prompt: String,
        tools: [any Tool],
        instructions: String
    ) async throws -> String {
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    func statusLines() -> [String] {
        let model = SystemLanguageModel.default
        var lines = [
            "Provider: apple",
            "Model availability: \(model.availability)",
        ]
        if model.availability == .available, #available(macOS 26.2, *) {
            lines.append("Supports streaming: yes")
        }
        return lines
    }
}

private struct OllamaModelClient: ModelClient {
    let config: ModelConfig
    let model: String
    let baseURL: URL
    let urlSession: URLSession
    let maxToolRounds: Int

    init(
        config: ModelConfig,
        model: String,
        baseURL: URL,
        maxToolRounds: Int = 12
    ) {
        self.config = config
        self.model = model
        self.baseURL = baseURL
        self.maxToolRounds = maxToolRounds
        self.urlSession = URLSession(configuration: .ephemeral)
    }

    func respond(
        prompt: String,
        tools: [any Tool],
        instructions: String
    ) async throws -> String {
        try await respondStream(prompt: prompt, tools: tools, instructions: instructions, onEvent: { _ in })
    }

    func respondStream(
        prompt: String,
        tools: [any Tool],
        instructions: String,
        onEvent: @escaping (ModelEvent) async -> Void
    ) async throws -> String {
        let installedModels = await OllamaModelDiscovery.installedModels(baseURL: baseURL)
        if !installedModels.isEmpty,
           !installedModels.contains(where: { $0.caseInsensitiveCompare(model) == .orderedSame }) {
            throw ModelClientFactoryError.modelNotInstalled(model: model)
        }

        let toolDefinitions = ToolBridge.toolDefinitions(for: tools)
        var messages: [OllamaOutgoingMessage] = [
            .system(instructions),
            .user(prompt),
        ]

        await onEvent(.status("thinking"))

        if toolDefinitions.isEmpty {
            let streamed = try await requestChatStreaming(messages: messages, onEvent: onEvent)
            await onEvent(.completed(streamed))
            return streamed
        }

        for _ in 0..<maxToolRounds {
            let assistant = try await requestChat(messages: messages, toolDefinitions: toolDefinitions)
            let content = assistant.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let toolCalls = assistant.toolCalls ?? []

            if !toolCalls.isEmpty {
                messages.append(.assistant(content: content, toolCalls: toolCalls))
                for toolCall in toolCalls {
                    await onEvent(.toolCall(name: toolCall.function.name))
                    let output = await ToolBridge.invoke(
                        toolName: toolCall.function.name,
                        argumentsJSON: toolCall.function.argumentsJSONString,
                        availableTools: tools
                    )
                    await onEvent(.toolResult(name: toolCall.function.name, outputPreview: String(output.prefix(120))))
                    messages.append(.tool(name: toolCall.function.name, content: output))
                }
                continue
            }

            if let content, !content.isEmpty {
                for chunk in streamingChunks(from: content) {
                    await onEvent(.token(chunk))
                }
                await onEvent(.completed(content))
                return content
            }

            await onEvent(.completed("(no response content)"))
            return "(no response content)"
        }

        throw OllamaClientError.toolLoopExceeded(maxToolRounds)
    }

    func statusLines() -> [String] {
        [
            "Provider: ollama",
            "Model: \(model)",
            "Base URL: \(baseURL.absoluteString)",
            "Supports streaming: simulated",
        ]
    }

    private func requestChat(
        messages: [OllamaOutgoingMessage],
        toolDefinitions: [[String: Any]]
    ) async throws -> OllamaAssistantMessage {
        var request = URLRequest(url: chatURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")

        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.jsonObject() },
            "stream": false,
        ]
        if !toolDefinitions.isEmpty {
            payload["tools"] = toolDefinitions
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ModelClientFactoryError.ollamaUnavailable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidHTTPResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw OllamaClientError.httpFailure(
                statusCode: http.statusCode,
                message: parseErrorMessage(data: data)
            )
        }

        let decoded: OllamaChatResponse
        do {
            decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw OllamaClientError.invalidResponseBody(raw: String(raw.prefix(1_200)))
        }

        if let error = decoded.error, !error.isEmpty {
            throw OllamaClientError.apiError(error)
        }

        guard let message = decoded.message else {
            throw OllamaClientError.emptyMessage
        }
        return message
    }

    private func requestChatStreaming(
        messages: [OllamaOutgoingMessage],
        onEvent: @escaping (ModelEvent) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: chatURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "model": model,
                "messages": messages.map { $0.jsonObject() },
                "stream": true,
            ],
            options: []
        )

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await urlSession.bytes(for: request)
        } catch {
            throw ModelClientFactoryError.ollamaUnavailable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaClientError.httpFailure(statusCode: http.statusCode, message: "(stream request failed)")
        }

        var full = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }

            if let chunk = try? JSONDecoder().decode(OllamaStreamChunk.self, from: data) {
                if let err = chunk.error, !err.isEmpty {
                    throw OllamaClientError.apiError(err)
                }
                if let token = chunk.message?.content, !token.isEmpty {
                    full += token
                    await onEvent(.token(token))
                }
                if chunk.done == true {
                    break
                }
            }
        }
        return full.isEmpty ? "(no response content)" : full
    }

    private func parseErrorMessage(data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(OllamaErrorEnvelope.self, from: data),
           let message = decoded.error,
           !message.isEmpty {
            return message
        }
        if let raw = String(data: data, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(raw.prefix(1_200))
        }
        return "(no error details)"
    }

    private func chatURL() -> URL {
        baseURL.appendingPathComponent("api").appendingPathComponent("chat")
    }
}

private enum OllamaClientError: LocalizedError {
    case invalidHTTPResponse
    case httpFailure(statusCode: Int, message: String)
    case apiError(String)
    case emptyMessage
    case invalidResponseBody(raw: String)
    case toolLoopExceeded(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Ollama returned a non-HTTP response."
        case .httpFailure(let statusCode, let message):
            return "Ollama request failed with status \(statusCode): \(message)"
        case .apiError(let message):
            return "Ollama error: \(message)"
        case .emptyMessage:
            return "Ollama returned an empty message."
        case .invalidResponseBody(let raw):
            return "Ollama returned an invalid response body: \(raw)"
        case .toolLoopExceeded(let rounds):
            return "Tool-calling loop exceeded \(rounds) rounds without a final answer."
        }
    }
}

private enum OllamaOutgoingMessage {
    case system(String)
    case user(String)
    case assistant(content: String?, toolCalls: [OllamaToolCall])
    case tool(name: String, content: String)

    func jsonObject() -> [String: Any] {
        switch self {
        case .system(let content):
            return ["role": "system", "content": content]
        case .user(let content):
            return ["role": "user", "content": content]
        case .assistant(let content, let toolCalls):
            var obj: [String: Any] = ["role": "assistant"]
            obj["content"] = content ?? ""
            if !toolCalls.isEmpty {
                obj["tool_calls"] = toolCalls.map { $0.jsonObject() }
            }
            return obj
        case .tool(let name, let content):
            return [
                "role": "tool",
                "tool_name": name,
                "content": content,
            ]
        }
    }
}

private struct OllamaChatResponse: Decodable {
    let message: OllamaAssistantMessage?
    let error: String?
}

private struct OllamaErrorEnvelope: Decodable {
    let error: String?
}

private struct OllamaStreamChunk: Decodable {
    let message: OllamaAssistantMessage?
    let done: Bool?
    let error: String?
}

private struct OllamaAssistantMessage: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OllamaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
}

private struct OllamaToolCall: Decodable {
    let function: FunctionCall

    struct FunctionCall: Decodable {
        let name: String
        let argumentsJSONString: String

        enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)

            if let text = try? container.decode(String.self, forKey: .arguments) {
                argumentsJSONString = Self.normalizeArgumentsJSONString(text) ?? "{}"
                return
            }
            if let json = try? container.decode([String: JSONValue].self, forKey: .arguments),
               let data = try? JSONSerialization.data(withJSONObject: json.mapValues({ $0.asAny }), options: []),
               let text = String(data: data, encoding: .utf8) {
                argumentsJSONString = text
                return
            }
            argumentsJSONString = "{}"
        }

        private static func normalizeArgumentsJSONString(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                return nil
            }
            guard let any = try? JSONSerialization.jsonObject(with: data, options: []),
                  JSONSerialization.isValidJSONObject(any),
                  let canonical = try? JSONSerialization.data(withJSONObject: any, options: []),
                  let text = String(data: canonical, encoding: .utf8) else {
                return nil
            }
            return text
        }
    }

    func jsonObject() -> [String: Any] {
        let argumentsObject: Any = {
            guard let data = function.argumentsJSONString.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return [String: Any]()
            }
            return decoded
        }()
        return [
            "type": "function",
            "function": [
                "name": function.name,
                "arguments": argumentsObject,
            ],
        ]
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    var asAny: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? Int(value) : value
        case .bool(let value):
            return value
        case .object(let map):
            return map.mapValues { $0.asAny }
        case .array(let values):
            return values.map { $0.asAny }
        case .null:
            return NSNull()
        }
    }
}
