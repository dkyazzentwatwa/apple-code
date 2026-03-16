import Foundation
import FoundationModels

struct WebSearchTool: Tool {
    let name = "webSearch"
    let description = "Search the web and return top results with URLs and snippets"

    @Generable
    struct Arguments {
        @Guide(description: "Search query")
        let query: String
        @Guide(description: "Number of results to return")
        let limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Error: 'query' is required." }

        let limit = max(1, min(arguments.limit ?? 5, 10))

        if let siteDomain = extractSiteDomain(from: query) {
            let siteResults = try await searchWithinSite(domain: siteDomain, limit: limit)
            if !siteResults.isEmpty {
                let lines = siteResults.enumerated().map { index, result in
                    var entry = "\(index + 1). \(result.title)\n   URL: \(result.url)"
                    if !result.snippet.isEmpty {
                        entry += "\n   Snippet: \(result.snippet)"
                    }
                    return entry
                }
                return lines.joined(separator: "\n")
            }
        }

        if let apiResults = try? await searchViaBraveAPI(query: query, limit: limit), !apiResults.isEmpty {
            let lines = apiResults.enumerated().map { index, result in
                var entry = "\(index + 1). \(result.title)\n   URL: \(result.url)"
                if !result.snippet.isEmpty {
                    entry += "\n   Snippet: \(result.snippet)"
                }
                return entry
            }
            return lines.joined(separator: "\n")
        }

        if let braveResults = try? await searchViaBraveJina(query: query, limit: limit), !braveResults.isEmpty {
            let lines = braveResults.enumerated().map { index, result in
                var entry = "\(index + 1). \(result.title)\n   URL: \(result.url)"
                if !result.snippet.isEmpty {
                    entry += "\n   Snippet: \(result.snippet)"
                }
                return entry
            }
            return lines.joined(separator: "\n")
        }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.bing.com/search?q=\(encoded)&count=\(limit)&setlang=en-US") else {
            return "Error: Failed to build search URL."
        }
        let bingCheck = ToolSafety.shared.checkURL(url)
        guard bingCheck.allowed else {
            return "Error: Search URL blocked by security policy (\(bingCheck.reason ?? "blocked"))."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Error: Unexpected response type from search."
            }
            guard (200..<300).contains(http.statusCode) else {
                return "Error: Search request failed with status \(http.statusCode)."
            }

            let html = WebTextUtils.decodeText(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type")) ?? ""
            if html.isEmpty {
                return "Error: Empty search response."
            }

            let lowerHTML = html.lowercased()
            if lowerHTML.contains("unfortunately, bots use")
                || lowerHTML.contains("please complete the following challenge")
                || lowerHTML.contains("captcha") {
                return "Error: Search provider challenge detected. Try a narrower query or use webFetch with a direct URL."
            }

            let results = parseBingResults(html: html, limit: limit)
            if results.isEmpty {
                return "No search results found for '\(query)'."
            }

            let lines = results.enumerated().map { index, result in
                var entry = "\(index + 1). \(result.title)\n   URL: \(result.url)"
                if !result.snippet.isEmpty {
                    entry += "\n   Snippet: \(result.snippet)"
                }
                return entry
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Error running web search: \(error.localizedDescription)"
        }
    }

    private func searchViaBraveAPI(
        query: String,
        limit: Int
    ) async throws -> [(title: String, url: String, snippet: String)]? {
        let apiKey = ProcessInfo.processInfo.environment["BRAVE_SEARCH_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "search_lang", value: "en"),
        ]
        guard let url = components?.url else { return nil }
        let urlCheck = ToolSafety.shared.checkURL(url)
        guard urlCheck.allowed else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else { return nil }

        let decoded = try JSONDecoder().decode(BraveWebSearchResponse.self, from: data)
        let mapped = decoded.web?.results?.compactMap { item -> (title: String, url: String, snippet: String)? in
            let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (item.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !url.isEmpty else { return nil }
            let snippet = item.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (title: title, url: url, snippet: String(snippet.prefix(300)))
        } ?? []
        return mapped.isEmpty ? nil : mapped
    }

    private struct BraveWebSearchResponse: Decodable {
        struct WebPayload: Decodable {
            struct WebResult: Decodable {
                let title: String?
                let url: String?
                let description: String?
            }

            let results: [WebResult]?
        }

        let web: WebPayload?
    }

    private func searchViaBraveJina(
        query: String,
        limit: Int
    ) async throws -> [(title: String, url: String, snippet: String)]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://r.jina.ai/http://search.brave.com/search?q=\(encoded)&source=web") else {
            return nil
        }
        let urlCheck = ToolSafety.shared.checkURL(url)
        guard urlCheck.allowed else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let body = WebTextUtils.decodeText(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type")),
              !body.isEmpty else {
            return nil
        }

        let lowerBody = body.lowercased()
        if lowerBody.contains("\"code\":451") || lowerBody.contains("securitycompromiseerror") {
            return nil
        }

        let lines = body.components(separatedBy: .newlines)
        let linkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#)
        let queryKeywords = buildQueryKeywords(query)
        var seen = Set<String>()
        var results: [(title: String, url: String, snippet: String)] = []

        for (index, line) in lines.enumerated() {
            guard let linkRegex else { break }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = linkRegex.matches(in: line, range: range)
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }

                let rawTitle = nsLine.substring(with: match.range(at: 1))
                let rawURL = nsLine.substring(with: match.range(at: 2))
                let title = cleanBraveTitle(rawTitle)
                let cleanedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !title.isEmpty else { continue }
                guard cleanedURL.hasPrefix("http://") || cleanedURL.hasPrefix("https://") else { continue }
                guard shouldKeepBraveResult(
                    url: cleanedURL,
                    title: title,
                    keywords: queryKeywords
                ) else { continue }
                guard seen.insert(cleanedURL).inserted else { continue }

                let snippet = extractBraveSnippet(lines: lines, from: index)
                results.append((title: title, url: cleanedURL, snippet: snippet))
                if results.count >= limit { break }
            }
            if results.count >= limit { break }
        }

        if results.isEmpty {
            for urlCandidate in extractBraveURLCandidates(from: body) {
                if results.count >= limit { break }
                guard shouldKeepBraveResult(url: urlCandidate, title: "", keywords: queryKeywords) else { continue }
                guard seen.insert(urlCandidate).inserted else { continue }
                let title = deriveTitle(from: urlCandidate)
                results.append((title: title, url: urlCandidate, snippet: "Found via web snapshot"))
            }
        }

        return results.isEmpty ? nil : results
    }

    private func cleanBraveTitle(_ rawTitle: String) -> String {
        var title = rawTitle
        title = title.replacingOccurrences(
            of: #"\!\[[^\]]*\]\([^)]+\)"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(of: "**", with: "")
        title = WebTextUtils.decodeHTMLEntities(title)
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldKeepBraveResult(url: String, title: String, keywords: [String]) -> Bool {
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased() else { return false }
        if host.contains("search.brave.com") { return false }
        if host.contains("imgs.search.brave.com") || host.contains("cdn.search.brave.com") { return false }
        if host == "brave.com" || host.hasSuffix(".brave.com") { return false }
        if host == "your-server.com" { return false }

        if !keywords.isEmpty {
            let haystack = "\(title.lowercased()) \(url.lowercased())"
            let keywordHit = keywords.contains { haystack.contains($0) }
            if !keywordHit { return false }
        }
        return true
    }

    private func extractBraveURLCandidates(from body: String) -> [String] {
        let pattern = #"https?://[^\s\)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var urls: [String] = []
        for match in matches {
            let raw = ns.substring(with: match.range)
            let cleaned = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;\"'"))
                .replacingOccurrences(of: "\\)", with: "", options: .regularExpression)
            if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
                urls.append(cleaned)
            }
        }
        return urls
    }

    private func deriveTitle(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return host }
        let last = path.split(separator: "/").last.map(String.init) ?? path
        let cleanedLast = last.replacingOccurrences(of: "-", with: " ")
        return "\(host) - \(cleanedLast)"
    }

    private func buildQueryKeywords(_ query: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "to", "up", "of", "for", "on", "in", "at",
            "and", "or", "how", "what", "when", "where", "is", "are", "web", "search"
        ]

        let tokens = query.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }

        return Array(Set(tokens))
    }

    private func extractBraveSnippet(lines: [String], from index: Int) -> String {
        guard index + 1 < lines.count else { return "" }
        let maxLookahead = min(lines.count - 1, index + 4)
        for j in (index + 1)...maxLookahead {
            let candidate = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { continue }
            if candidate.hasPrefix("[") || candidate.hasPrefix("![") { continue }
            if candidate.hasPrefix("#") { continue }
            if candidate.lowercased().hasPrefix("view all") { continue }
            if candidate.count > 8 {
                return String(candidate.prefix(220))
            }
        }
        return ""
    }

    private func parseBingResults(html: String, limit: Int) -> [(title: String, url: String, snippet: String)] {
        let pattern = #"(?is)<li[^>]*class="[^"]*b_algo[^"]*"[^>]*>.*?<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?</h2>.*?(?:<p[^>]*>(.*?)</p>)?.*?</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var results: [(title: String, url: String, snippet: String)] = []

        for match in matches {
            if results.count >= limit { break }
            guard match.numberOfRanges >= 3 else { continue }

            let url = capture(ns: ns, in: match, at: 1)
            let rawTitle = capture(ns: ns, in: match, at: 2)
            let rawSnippet = match.numberOfRanges > 3 ? capture(ns: ns, in: match, at: 3) : ""

            let title = WebTextUtils.stripHTML(rawTitle)
            let snippet = String(WebTextUtils.stripHTML(rawSnippet).prefix(300))
            let cleanedURL = unwrapBingURL(WebTextUtils.decodeHTMLEntities(url))

            guard !title.isEmpty, cleanedURL.hasPrefix("http") else { continue }
            results.append((title: title, url: cleanedURL, snippet: snippet))
        }

        return results
    }

    private func unwrapBingURL(_ url: String) -> String {
        guard let parsed = URL(string: url),
              let host = parsed.host?.lowercased(),
              host.contains("bing.com"),
              parsed.path == "/ck/a" else {
            return url
        }

        guard let components = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "u" })?.value,
              encoded.hasPrefix("a1") else {
            return url
        }

        let payload = String(encoded.dropFirst(2))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let decoded = String(data: data, encoding: .utf8),
              decoded.hasPrefix("http") else {
            return url
        }
        return decoded
    }

    private func extractSiteDomain(from query: String) -> String? {
        let lower = query.lowercased()
        if let range = lower.range(of: "site:") {
            let tail = lower[range.upperBound...]
            let token = tail.split(separator: " ").first.map(String.init) ?? ""
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n/"))
            if cleaned.contains(".") {
                return cleaned
            }
        }

        let tokens = lower.split(separator: " ").map(String.init)
        for token in tokens {
            let cleaned = token
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n/"))
            if cleaned.contains(".") && !cleaned.contains("/") {
                return cleaned
            }
        }

        return nil
    }

    private func searchWithinSite(domain: String, limit: Int) async throws -> [(title: String, url: String, snippet: String)] {
        let session = URLSession(configuration: .ephemeral)
        let candidateURLs = [
            "https://\(domain)",
            "https://\(domain)/archive",
        ]

        var collected: [(title: String, url: String, snippet: String)] = []
        var seen = Set<String>()

        for rawURL in candidateURLs {
            guard let url = URL(string: rawURL) else { continue }
            let urlCheck = ToolSafety.shared.checkURL(url)
            guard urlCheck.allowed else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html = WebTextUtils.decodeText(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type")) else {
                continue
            }

            let links = extractLinks(html: html, baseURL: url, domain: domain)
            for link in links {
                if collected.count >= limit { break }
                if seen.insert(link.url).inserted {
                    collected.append(link)
                }
            }
            if collected.count >= limit { break }
        }

        return collected
    }

    private func extractLinks(
        html: String,
        baseURL: URL,
        domain: String
    ) -> [(title: String, url: String, snippet: String)] {
        let pattern = #"(?is)<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var results: [(title: String, url: String, snippet: String)] = []
        for match in matches {
            let hrefRaw = capture(ns: ns, in: match, at: 1)
            let titleRaw = capture(ns: ns, in: match, at: 2)

            let title = WebTextUtils.stripHTML(titleRaw)
            if title.isEmpty || title.count < 3 { continue }

            let href = WebTextUtils.decodeHTMLEntities(hrefRaw)
            guard let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            guard let host = absoluteURL.host?.lowercased(), host.contains(domain) else { continue }

            let path = absoluteURL.path.lowercased()
            if path == "/" || path.hasPrefix("/api/") || path.contains("/subscribe") || path.contains("/signin") {
                continue
            }

            results.append((title: title, url: absoluteURL.absoluteString, snippet: "Found on \(domain)"))
        }

        return results
    }

    private func capture(ns: NSString, in match: NSTextCheckingResult, at index: Int) -> String {
        guard index < match.numberOfRanges else { return "" }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return ns.substring(with: range)
    }
}
