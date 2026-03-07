import Foundation

enum OllamaModelDiscovery {
    static let recommendedQwenModels: [String] = [
        "qwen3.5:4b",
        "qwen3.5:2b",
        "qwen3.5:0.8b",
    ]

    static func installedModels(baseURL: URL) async -> [String] {
        let cliModels = installedModelsFromCLI()
        if !cliModels.isEmpty {
            return cliModels
        }
        let apiModels = await installedModelsFromAPI(baseURL: baseURL)
        return apiModels
    }

    static func preferredDefaultModel(from installedModels: [String]) -> String? {
        guard !installedModels.isEmpty else { return nil }
        let lower = installedModels.map { $0.lowercased() }

        if let idx = lower.firstIndex(where: { $0.contains("qwen3.5") && ($0.contains(":4b") || $0.contains(" 4b")) }) {
            return installedModels[idx]
        }
        if let idx = lower.firstIndex(where: { $0.contains("qwen3.5") && ($0.contains(":2b") || $0.contains(" 2b")) }) {
            return installedModels[idx]
        }
        if let idx = lower.firstIndex(where: {
            $0.contains("qwen3.5") && ($0.contains(":0.8b") || $0.contains(":0_8b") || $0.contains(":8b-small"))
        }) {
            return installedModels[idx]
        }
        return installedModels.first
    }

    private static func installedModelsFromCLI() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "list"]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0,
              let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard lines.count > 1 else { return [] }

        var models: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            if let first = parts.first {
                models.append(String(first))
            }
        }
        return models
    }

    private static func installedModelsFromAPI(baseURL: URL) async -> [String] {
        guard let normalizedBaseURL = try? ModelConfig.normalizeBaseURL(baseURL.absoluteString) else {
            return []
        }

        let tagsURL = normalizedBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tags")
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models.map(\.name)
        } catch {
            return []
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct OllamaModel: Decodable {
        let name: String
    }
    let models: [OllamaModel]
}
