import Foundation

final class ConversationViewport {
    struct Entry {
        let id: Int
        let role: String
        let content: String
    }

    private(set) var entries: [Entry] = []
    private let maxEntries: Int
    private var nextID: Int = 1
    private var wrappedCacheByEntryID: [Int: [String]] = [:]
    private var wrappedCacheWidth: Int?
    private var scrollOffsetFromBottom: Int = 0

    init(maxEntries: Int = 300) {
        self.maxEntries = maxEntries
    }

    func append(role: String, content: String) {
        let trimmed = content.trimmingCharacters(in: .newlines)
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, role: role, content: trimmed))
        scrollOffsetFromBottom = 0
        if entries.count > maxEntries {
            let removeCount = entries.count - maxEntries
            let removed = entries.prefix(removeCount)
            for entry in removed {
                wrappedCacheByEntryID.removeValue(forKey: entry.id)
            }
            entries.removeFirst(removeCount)
        }
    }

    func reset() {
        entries.removeAll(keepingCapacity: true)
        wrappedCacheByEntryID.removeAll(keepingCapacity: true)
        wrappedCacheWidth = nil
        scrollOffsetFromBottom = 0
    }

    func recentEntries(limit: Int) -> [Entry] {
        guard limit > 0 else { return [] }
        return Array(entries.suffix(limit))
    }

    func entry(id: Int) -> Entry? {
        entries.first(where: { $0.id == id })
    }

    func invalidateWrapCache() {
        wrappedCacheByEntryID.removeAll(keepingCapacity: true)
        wrappedCacheWidth = nil
    }

    func scrollBy(_ delta: Int, width: Int, maxLines: Int) {
        guard delta != 0 else { return }
        let maxOffset = maxScrollOffset(width: width, maxLines: maxLines)
        let updated = scrollOffsetFromBottom + delta
        scrollOffsetFromBottom = min(max(0, updated), maxOffset)
    }

    func scrollToBottom() {
        scrollOffsetFromBottom = 0
    }

    func scrollState(width: Int, maxLines: Int) -> (offset: Int, maxOffset: Int) {
        let maxOffset = maxScrollOffset(width: width, maxLines: maxLines)
        let clamped = min(max(0, scrollOffsetFromBottom), maxOffset)
        return (offset: clamped, maxOffset: maxOffset)
    }

    func visibleLines(width: Int, maxLines: Int) -> [String] {
        guard width > 4, maxLines > 0 else { return [] }
        if wrappedCacheWidth != width {
            wrappedCacheWidth = width
            wrappedCacheByEntryID.removeAll(keepingCapacity: true)
        }

        let rendered = renderedLines(width: width)

        // Windowing: render only what fits the viewport height.
        if rendered.count <= maxLines { return rendered }
        let maxOffset = max(0, rendered.count - maxLines)
        let clamped = min(max(0, scrollOffsetFromBottom), maxOffset)
        scrollOffsetFromBottom = clamped
        let end = rendered.count - clamped
        let start = max(0, end - maxLines)
        return Array(rendered[start..<end])
    }

    private func maxScrollOffset(width: Int, maxLines: Int) -> Int {
        guard width > 4, maxLines > 0 else { return 0 }
        let rendered = renderedLines(width: width)
        return max(0, rendered.count - maxLines)
    }

    private func renderedLines(width: Int) -> [String] {
        var rendered: [String] = []
        for entry in entries {
            let labelRaw = "\(entry.role): "
            let wrapped: [String]
            if let cached = wrappedCacheByEntryID[entry.id] {
                wrapped = cached
            } else {
                let computed = wrapText(entry.content, width: max(8, width - labelRaw.count))
                wrappedCacheByEntryID[entry.id] = computed
                wrapped = computed
            }
            if wrapped.isEmpty {
                rendered.append(labelRaw)
            } else {
                rendered.append(labelRaw + wrapped[0])
                for continuation in wrapped.dropFirst() {
                    rendered.append(String(repeating: " ", count: labelRaw.count) + continuation)
                }
            }
            rendered.append("")
        }
        return rendered
    }

    private func wrapText(_ text: String, width: Int) -> [String] {
        let paragraphs = text.components(separatedBy: .newlines)
        var result: [String] = []

        for para in paragraphs {
            if para.isEmpty {
                result.append("")
                continue
            }

            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                if line.isEmpty {
                    line = w
                } else if line.count + 1 + w.count <= width {
                    line += " " + w
                } else {
                    result.append(line)
                    line = w
                }

                while line.count > width {
                    let head = String(line.prefix(width))
                    result.append(head)
                    line = String(line.dropFirst(width))
                }
            }
            result.append(line)
        }

        return result
    }
}
