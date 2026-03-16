import Foundation
import FoundationModels

struct WebFetchTool: Tool {
    let name = "webFetch"
    let description = "Fetch a URL and return readable text content"

    @Generable
    struct Arguments {
        @Guide(description: "HTTP or HTTPS URL to fetch")
        let url: String
        @Guide(description: "Maximum characters in response body text")
        let maxChars: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let requestedURL = arguments.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: requestedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return "Error: URL must be valid and use http or https."
        }
        let urlCheck = ToolSafety.shared.checkURL(url)
        guard urlCheck.allowed else {
            return "Error: URL blocked by security policy (\(urlCheck.reason ?? "blocked"))."
        }

        let maxChars = max(1000, min(arguments.maxChars ?? 12_000, 30_000))

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/json,text/plain,*/*", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Error: Unexpected response type."
            }

            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let finalURL = http.url?.absoluteString ?? requestedURL

            let isHTML = contentType.contains("text/html")
            let isTextLike = contentType.hasPrefix("text/")
                || contentType.contains("json")
                || contentType.contains("xml")
                || contentType.contains("javascript")

            if !isHTML && !isTextLike {
                return """
                URL: \(finalURL)
                Status: \(http.statusCode)
                Content-Type: \(contentType.isEmpty ? "unknown" : contentType)
                Body-Bytes: \(data.count)
                Note: Non-text content not returned.
                """
            }

            guard let decoded = WebTextUtils.decodeText(data: data, contentType: contentType) else {
                return """
                URL: \(finalURL)
                Status: \(http.statusCode)
                Content-Type: \(contentType.isEmpty ? "unknown" : contentType)
                Error: Could not decode response body as text.
                """
            }

            if isHTML, let compactNews = extractCNNHeadlinesIfApplicable(html: decoded, finalURL: finalURL) {
                return compactNews
            }

            var readable = isHTML ? WebTextUtils.htmlToText(decoded) : WebTextUtils.normalizeWhitespace(decoded)

            if shouldTrySubstackArchiveFallback(url: http.url ?? url, text: readable) {
                if let archiveSnippet = try await fetchSubstackArchiveSnippet(baseURL: http.url ?? url, maxChars: maxChars / 2) {
                    readable += "\n\n[Archive Snapshot]\n\(archiveSnippet)"
                }
            }

            let (truncatedText, isTruncated) = WebTextUtils.truncate(readable, maxChars: maxChars)
            let truncationNote = isTruncated ? "\n... [truncated at \(maxChars) chars]" : ""

            return """
            URL: \(finalURL)
            Status: \(http.statusCode)
            Content-Type: \(contentType.isEmpty ? "unknown" : contentType)

            \(truncatedText)\(truncationNote)
            """
        } catch {
            return "Error fetching URL: \(error.localizedDescription)"
        }
    }

    private func shouldTrySubstackArchiveFallback(url: URL, text: String) -> Bool {
        guard let host = url.host?.lowercased(), host.contains("substack.com") else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        guard path == "/" else { return false }
        return text.lowercased().contains("this site requires javascript")
    }

    private func fetchSubstackArchiveSnippet(baseURL: URL, maxChars: Int) async throws -> String? {
        guard let host = baseURL.host else { return nil }
        guard let archiveURL = URL(string: "https://\(host)/archive") else { return nil }
        let archiveCheck = ToolSafety.shared.checkURL(archiveURL)
        guard archiveCheck.allowed else { return nil }

        var request = URLRequest(url: archiveURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("apple-code/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        guard let decoded = WebTextUtils.decodeText(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type")) else {
            return nil
        }
        let archiveText = WebTextUtils.htmlToText(decoded)
        let (truncated, _) = WebTextUtils.truncate(archiveText, maxChars: max(1000, maxChars))
        return truncated
    }

    private func extractCNNHeadlinesIfApplicable(html: String, finalURL: String) -> String? {
        guard let parsed = URL(string: finalURL),
              let host = parsed.host?.lowercased(),
              host.contains("cnn.com") else {
            return nil
        }

        let path = parsed.path.isEmpty ? "/" : parsed.path
        guard path == "/" else { return nil }

        var rows = extractCNNStructuredHeadlines(html: html, baseURL: parsed)
        if rows.count < 8 {
            rows += extractCNNFallbackAnchors(html: html, baseURL: parsed)
        }

        rows = dedupeAndFilterCNNRows(rows, limit: 12)
        guard !rows.isEmpty else { return nil }

        let lines = rows.enumerated().map { idx, row in
            "\(idx + 1). \(row.title)\n   URL: \(row.url)"
        }.joined(separator: "\n")

        return """
        URL: \(finalURL)
        Status: 200
        Content-Type: text/html; charset=utf-8

        Top Headlines:
        \(lines)
        """
    }

    private func extractCNNStructuredHeadlines(html: String, baseURL: URL) -> [(title: String, url: String)] {
        let patterns = [
            #"(?is)<a[^>]+href="([^"]+)"[^>]*>.*?<span[^>]*class="[^"]*container__headline-text[^"]*"[^>]*>(.*?)</span>.*?</a>"#,
            #"(?is)<a[^>]+href="([^"]+)"[^>]*class="[^"]*live-story-updates-item__a[^"]*"[^>]*>.*?<span[^>]*class="[^"]*live-story-updates-item__headline[^"]*"[^>]*>(.*?)</span>.*?</a>"#,
        ]

        var results: [(title: String, url: String)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let hrefRaw = capture(ns: ns, in: match, at: 1)
                let titleRaw = capture(ns: ns, in: match, at: 2)
                guard let row = makeCNNRow(hrefRaw: hrefRaw, titleRaw: titleRaw, baseURL: baseURL) else { continue }
                results.append(row)
            }
        }
        return results
    }

    private func extractCNNFallbackAnchors(html: String, baseURL: URL) -> [(title: String, url: String)] {
        let pattern = #"(?is)<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var results: [(title: String, url: String)] = []

        for match in matches {
            let hrefRaw = capture(ns: ns, in: match, at: 1)
            let titleRaw = capture(ns: ns, in: match, at: 2)
            guard let row = makeCNNRow(hrefRaw: hrefRaw, titleRaw: titleRaw, baseURL: baseURL) else { continue }
            results.append(row)
        }

        return results
    }

    private func makeCNNRow(hrefRaw: String, titleRaw: String, baseURL: URL) -> (title: String, url: String)? {
        let href = WebTextUtils.decodeHTMLEntities(hrefRaw)
        guard let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard let articleHost = absoluteURL.host?.lowercased(), articleHost.contains("cnn.com") else { return nil }

        let path = absoluteURL.path.lowercased()
        guard isLikelyCNNStoryPath(path) else { return nil }

        let title = normalizeCNNHeadline(titleRaw)
        guard !title.isEmpty, title.count >= 20, title.count <= 220 else { return nil }
        guard !isDiscardedCNNHeadline(title) else { return nil }

        return (title: title, url: absoluteURL.absoluteString)
    }

    private func dedupeAndFilterCNNRows(_ rows: [(title: String, url: String)], limit: Int) -> [(title: String, url: String)] {
        var seen = Set<String>()
        var filtered: [(title: String, url: String)] = []

        for row in rows {
            if filtered.count >= limit { break }
            let key = "\(row.title.lowercased())|\(row.url)"
            if seen.insert(key).inserted {
                filtered.append(row)
            }
        }

        return filtered
    }

    private func normalizeCNNHeadline(_ raw: String) -> String {
        var text = WebTextUtils.stripHTML(raw)
        text = text.replacingOccurrences(of: "&bull;", with: " ")
        text = text.replacingOccurrences(of: #"^\s*[•·\-]+\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+\d{1,2}:\d{2}(?:\s*CNN)?\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyCNNStoryPath(_ path: String) -> Bool {
        if path.isEmpty || path == "/" { return false }
        if path == "/terms" || path == "/privacy" || path == "/audio" { return false }
        if path.hasPrefix("/audio/") || path.hasPrefix("/podcasts/") { return false }
        if path.hasPrefix("/videos") { return false }
        if path.hasPrefix("/account") || path.hasPrefix("/subscribe") || path.hasPrefix("/newsletters") { return false }

        if path.contains("/live-news/") { return true }
        if path.range(of: #"/20\d{2}/"#, options: .regularExpression) != nil { return true }

        let segments = path.split(separator: "/")
        return segments.count >= 3
    }

    private func isDiscardedCNNHeadline(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower == "watch cnn"
            || lower.contains("terms of use")
            || lower.contains("privacy policy")
            || lower.contains("all cnn audio podcasts")
            || lower.contains("cnn audio podcasts")
            || lower.contains("listen")
    }

    private func capture(ns: NSString, in match: NSTextCheckingResult, at index: Int) -> String {
        guard index < match.numberOfRanges else { return "" }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return ns.substring(with: range)
    }
}
