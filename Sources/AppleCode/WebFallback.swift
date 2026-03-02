import Foundation
import FoundationModels

func extractFirstHTTPURL(from text: String) -> String? {
    let pattern = #"https?://[^\s<>"'\)\]]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    return ns.substring(with: match.range)
}

func looksLikeWebAccessRefusal(_ text: String) -> Bool {
    let lower = text.lowercased()
    let refusalSignal = lower.contains("can't access")
        || lower.contains("cannot access")
        || lower.contains("unable to access")
        || lower.contains("unable to fetch")
        || lower.contains("couldn't retrieve")
        || lower.contains("could not retrieve")
        || lower.contains("can't retrieve")
        || lower.contains("cannot retrieve")
        || lower.contains("unable to retrieve")

    let webSignal = lower.contains("website")
        || lower.contains("external")
        || lower.contains("substack")
        || lower.contains("internet")
        || lower.contains("url")
        || lower.contains("link")

    return refusalSignal && webSignal
}

func looksLikeGenericRefusal(_ text: String) -> Bool {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let refusalPhrases = [
        "i'm sorry",
        "i am sorry",
        "i can't assist",
        "i cannot assist",
        "i can't help",
        "i cannot help",
        "i can't fulfill",
        "i cannot fulfill",
        "i'm unable",
        "i am unable",
        "unable to comply",
        "can't do that",
        "cannot do that",
    ]
    guard refusalPhrases.contains(where: { lower.contains($0) }) else { return false }

    // Keep this fallback for terse refusals, not normal informative responses.
    let likelyTerseRefusal = lower.count <= 320
    let hasStructuredOutput = lower.contains("url:")
        || lower.contains("top headlines:")
        || lower.contains("1.")
        || lower.contains("2.")

    return likelyTerseRefusal && !hasStructuredOutput
}

func looksLikeWebIntentPrompt(_ text: String) -> Bool {
    if extractFirstHTTPURL(from: text) != nil {
        return true
    }
    let lower = text.lowercased()
    return lower.contains("web")
        || lower.contains("website")
        || lower.contains("url")
        || lower.contains("link")
        || lower.contains("news")
        || lower.contains("headline")
        || lower.contains("latest")
        || lower.contains("search")
        || lower.contains("fetch")
}

func looksLikeThinWebAnswer(_ text: String) -> Bool {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.count > 260 { return false }

    let hasURL = extractFirstHTTPURL(from: text) != nil
    let hasNumberedList = text.range(of: #"(?m)^\s*\d+\.\s+"#, options: .regularExpression) != nil
    let hasBullets = text.contains("\n- ") || text.contains("\n* ")
    return hasURL && !hasNumberedList && !hasBullets
}

func shouldUseWebFallback(userPrompt: String, modelReply: String) -> Bool {
    let lowerReply = modelReply.lowercased()
    let hasRefusalWord = lowerReply.contains("can't")
        || lowerReply.contains("cannot")
        || lowerReply.contains("unable")
        || lowerReply.contains("couldn't")
        || lowerReply.contains("could not")
    let hasWebFailureWord = lowerReply.contains("access")
        || lowerReply.contains("retrieve")
        || lowerReply.contains("browse")
        || lowerReply.contains("fetch")
    let refusalSignal = hasRefusalWord && hasWebFailureWord

    if looksLikeWebAccessRefusal(modelReply) {
        return true
    }
    if looksLikeWebIntentPrompt(userPrompt),
       (refusalSignal || looksLikeGenericRefusal(modelReply) || looksLikeThinWebAnswer(modelReply)) {
        return true
    }
    return false
}

func extractToolOutputURLs(_ text: String, limit: Int = 3) -> [String] {
    var urls: [String] = []
    let lines = text.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("url:") else { continue }
        let candidate = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
        if candidate.hasPrefix("http://") || candidate.hasPrefix("https://") {
            urls.append(candidate)
        }
        if urls.count >= limit { break }
    }
    return urls
}

func buildDirectHeadlineSummary(userPrompt: String, fetchedContext: String) -> String? {
    let lowerPrompt = userPrompt.lowercased()
    let wantsNews = lowerPrompt.contains("latest")
        || lowerPrompt.contains("news")
        || lowerPrompt.contains("headline")
    guard wantsNews else { return nil }
    guard fetchedContext.contains("Top Headlines:") else { return nil }

    let sourceURL = extractToolOutputURLs(fetchedContext, limit: 1).first
    let lines = fetchedContext.components(separatedBy: .newlines)
    var items: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            items.append(trimmed)
            if items.count >= 8 { break }
        }
    }

    guard !items.isEmpty else { return nil }
    let list = items.joined(separator: "\n")
    if let sourceURL {
        return """
        Latest CNN headlines:
        \(list)

        Source: \(sourceURL)
        """
    }
    return """
    Latest headlines:
    \(list)
    """
}

func buildSourceListFallback(_ fetchedContext: String, maxItems: Int = 5) -> String? {
    let lines = fetchedContext.components(separatedBy: .newlines)
    var items: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            items.append(trimmed)
            if items.count >= maxItems { break }
        }
    }

    if !items.isEmpty {
        return """
        I couldn't produce a full summary, but here are relevant results:
        \(items.joined(separator: "\n"))
        """
    }

    let urls = extractToolOutputURLs(fetchedContext, limit: maxItems)
    if !urls.isEmpty {
        let numbered = urls.enumerated().map { index, url in
            "\(index + 1). \(url)"
        }.joined(separator: "\n")
        return """
        I couldn't produce a full summary, but here are useful sources:
        \(numbered)
        """
    }
    return nil
}

func resolveWebRefusalFallback(
    userPrompt: String,
    modelReply: String,
    instructions: String,
    timeoutSeconds: Int
) async -> String? {
    guard shouldUseWebFallback(userPrompt: userPrompt, modelReply: modelReply) else { return nil }

    let fetchedContext: String
    do {
        if let url = extractFirstHTTPURL(from: userPrompt) {
            fetchedContext = try await WebFetchTool().call(arguments: .init(url: url, maxChars: 5_500))
        } else {
            let search = try await WebSearchTool().call(arguments: .init(query: userPrompt, limit: 5))
            var combined = "Web search snapshot:\n\(search)"
            if let topURL = extractToolOutputURLs(search, limit: 1).first {
                let topFetch = try? await WebFetchTool().call(arguments: .init(url: topURL, maxChars: 3_000))
                if let topFetch, !topFetch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    combined += "\n\nTop result content:\n\(topFetch)"
                }
            }
            fetchedContext = combined
        }
    } catch {
        return "I tried to fetch the page directly but failed: \(error.localizedDescription)"
    }

    if let direct = buildDirectHeadlineSummary(userPrompt: userPrompt, fetchedContext: fetchedContext) {
        return direct
    }

    let followupPrompt = """
    User request: \(userPrompt)

    You can answer this now using the fetched page content below.
    Provide a concise, actionable answer and include source URLs you used.
    If data is missing, clearly say what is missing.

    Fetched page content:
    \(fetchedContext)
    """

    let session = LanguageModelSession(tools: [], instructions: instructions)
    do {
        return try await withResponseTimeout(seconds: timeoutSeconds) {
            let response = try await session.respond(to: followupPrompt)
            let content = response.content
            if shouldUseWebFallback(userPrompt: userPrompt, modelReply: content) || looksLikeGenericRefusal(content) {
                return buildSourceListFallback(fetchedContext) ?? content
            }
            return content
        }
    } catch {
        return "I fetched the page but couldn't produce a final summary: \(error.localizedDescription)"
    }
}
