import Foundation
import FoundationModels
import CoreGraphics
import CoreText

struct CreatePDFTool: Tool {
    let name = "createPDF"
    let description = "Create a PDF file from plain text content"

    @Generable
    struct Arguments {
        @Guide(description: "Output PDF file path")
        let path: String
        @Guide(description: "PDF title")
        let title: String?
        @Guide(description: "Main text content")
        let content: String
    }

    func call(arguments: Arguments) async throws -> String {
        let check = ToolSafety.shared.checkPath(arguments.path, forWrite: true)
        guard check.allowed else {
            return "Error: Access denied for path '\(arguments.path)' (\(check.reason ?? "blocked"))."
        }

        let outputURL = URL(fileURLWithPath: check.resolvedPath)
        let directory = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return "Error creating output directory: \(error.localizedDescription)"
        }

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return "Error: Could not initialize PDF context."
        }

        let title = arguments.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseContent = arguments.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText: String
        if !title.isEmpty && !baseContent.isEmpty {
            fullText = "\(title)\n\n\(baseContent)"
        } else if !title.isEmpty {
            fullText = title
        } else if !baseContent.isEmpty {
            fullText = baseContent
        } else {
            fullText = " "
        }

        let mutable = NSMutableAttributedString(string: fullText)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        mutable.addAttributes([
            NSAttributedString.Key(kCTFontAttributeName as String): bodyFont
        ], range: NSRange(location: 0, length: mutable.length))

        if !title.isEmpty {
            let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil)
            mutable.addAttributes([
                NSAttributedString.Key(kCTFontAttributeName as String): titleFont
            ], range: NSRange(location: 0, length: min(title.count, mutable.length)))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(mutable as CFAttributedString)
        let textRect = CGRect(x: 54, y: 54, width: pageRect.width - 108, height: pageRect.height - 108)
        let path = CGPath(rect: textRect, transform: nil)

        var currentRange = CFRange(location: 0, length: 0)
        var pageCount = 0
        let maxPages = 100

        while currentRange.location < mutable.length && pageCount < maxPages {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 { break }
            currentRange.location += visibleRange.length
            pageCount += 1
        }

        context.closePDF()

        if pageCount == 0 {
            return "Error: PDF generation produced zero pages."
        }
        let truncatedNote = currentRange.location < mutable.length
            ? " (truncated at \(maxPages) pages)"
            : ""
        return "Created PDF at \(check.resolvedPath) (\(pageCount) page(s))\(truncatedNote)"
    }
}
