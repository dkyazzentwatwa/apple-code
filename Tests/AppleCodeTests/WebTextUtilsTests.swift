import XCTest
@testable import apple_code

final class WebTextUtilsTests: XCTestCase {
    func testParseCharsetFromContentType() {
        XCTAssertEqual(WebTextUtils.parseCharset("text/html; charset=UTF-8"), "utf-8")
        XCTAssertNil(WebTextUtils.parseCharset(nil))
    }

    func testDecodeTextFallsBackToUtf8() {
        let data = Data("hello".utf8)
        XCTAssertEqual(WebTextUtils.decodeText(data: data, contentType: nil), "hello")
    }

    func testDecodeEntitiesAndStripHtml() {
        let html = "<p>Hello &amp; goodbye &lt;world&gt;</p>"
        XCTAssertEqual(WebTextUtils.stripHTML(html), "Hello & goodbye <world>")
    }

    func testHtmlToTextRemovesScriptAndStyle() {
        let html = "<style>.x{color:red}</style><script>alert(1)</script><h1>Title</h1><p>Body</p>"
        XCTAssertEqual(WebTextUtils.htmlToText(html), "Title Body")
    }

    func testNormalizeWhitespaceAndTruncate() {
        XCTAssertEqual(WebTextUtils.normalizeWhitespace(" a\n\t b  c "), "a b c")
        let truncated = WebTextUtils.truncate("abcdef", maxChars: 3)
        XCTAssertEqual(truncated.text, "abc")
        XCTAssertTrue(truncated.truncated)

        let notTruncated = WebTextUtils.truncate("abc", maxChars: 5)
        XCTAssertEqual(notTruncated.text, "abc")
        XCTAssertFalse(notTruncated.truncated)
    }
}
