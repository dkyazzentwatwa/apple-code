import Foundation

/// Manages conversation context budgets and rolling-window pruning.
struct TokenBudgetManager {
    /// Approximate per-provider token limits.
    /// AFM uses ~4096; Ollama defaults to 4096 but can be higher.
    static func tokenBudget(for provider: ProviderKind) -> Int {
        switch provider {
        case .apple:  return 4096
        case .ollama: return 8192
        }
    }

    /// Estimate tokens for a string (rough 4-chars-per-token heuristic).
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Estimate total tokens for all messages in a session.
    static func estimatedUsage(messages: [Message]) -> Int {
        messages.reduce(0) { $0 + estimateTokens($1.content) }
    }

    /// Prune messages to fit within `budget` tokens using a rolling window.
    /// Always preserves the first user message as an anchor (index 0).
    /// Returns the pruned message array.
    static func prune(messages: [Message], budget: Int) -> [Message] {
        guard estimatedUsage(messages: messages) > budget else { return messages }
        guard !messages.isEmpty else { return messages }

        // Always keep the first message as an anchor
        let anchor = messages[0]
        let anchorTokens = estimateTokens(anchor.content)

        var kept: [Message] = [anchor]
        var keptTokens = anchorTokens

        // Add recent messages (from the end) until we exceed budget
        for msg in messages.dropFirst().reversed() {
            let cost = estimateTokens(msg.content)
            if keptTokens + cost <= budget {
                kept.insert(msg, at: 1)
                keptTokens += cost
            } else {
                break
            }
        }

        return kept
    }

    /// Build a compact summary prompt that asks the model to summarize old turns.
    static func buildCompactSummaryPrompt(messages: [Message]) -> String {
        let transcript = messages.map { msg -> String in
            let role = msg.role.lowercased() == "assistant" ? "Assistant" : "User"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")

        return """
        Summarize the key points from this conversation in 2-4 concise bullet points. \
        Focus on facts, decisions, and code changes made. Be brief.

        Conversation:
        \(transcript)
        """
    }
}
