import Foundation

enum WebTextUtils {
    static func decodeText(data: Data, contentType: String?) -> String? {
        if let charset = parseCharset(contentType),
           let encoding = String.Encoding(ianaCharsetName: charset),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return nil
    }

    static func htmlToText(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        let withoutTags = withoutScripts.replacingOccurrences(
            of: "(?is)<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return normalizeWhitespace(decodeHTMLEntities(withoutTags))
    }

    static func normalizeWhitespace(_ input: String) -> String {
        input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripHTML(_ input: String) -> String {
        let withoutTags = input.replacingOccurrences(
            of: "(?is)<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return normalizeWhitespace(decodeHTMLEntities(withoutTags))
    }

    static func decodeHTMLEntities(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    static func parseCharset(_ contentType: String?) -> String? {
        guard let contentType = contentType else { return nil }
        let parts = contentType.components(separatedBy: ";")
        for raw in parts {
            let part = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if part.hasPrefix("charset=") {
                return String(part.dropFirst("charset=".count))
            }
        }
        return nil
    }

    static func truncate(_ input: String, maxChars: Int) -> (text: String, truncated: Bool) {
        guard input.count > maxChars else { return (input, false) }
        return (String(input.prefix(maxChars)), true)
    }
}

private extension String.Encoding {
    init?(ianaCharsetName: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaCharsetName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        self = String.Encoding(rawValue: nsEncoding)
    }
}
