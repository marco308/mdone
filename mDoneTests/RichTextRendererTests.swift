import XCTest
@testable import mDone

final class RichTextRendererTests: XCTestCase {
    // MARK: - containsHTML

    func testContainsHTMLDetectsParagraphTag() {
        XCTAssertTrue(RichTextRenderer.containsHTML("<p>hello</p>"))
    }

    func testContainsHTMLDetectsListMarkup() {
        XCTAssertTrue(RichTextRenderer.containsHTML("<ul><li>one</li><li>two</li></ul>"))
    }

    func testContainsHTMLIgnoresPlainText() {
        XCTAssertFalse(RichTextRenderer.containsHTML("Just a normal description with no tags."))
    }

    func testContainsHTMLIgnoresMarkdownAutolink() {
        // Markdown autolinks have no closing tag, so they must not be routed to the HTML parser.
        XCTAssertFalse(RichTextRenderer.containsHTML("See <https://example.com> for details."))
    }

    func testContainsHTMLIgnoresPlainAngleBrackets() {
        XCTAssertFalse(RichTextRenderer.containsHTML("2 < 3 and 5 > 4"))
        XCTAssertFalse(RichTextRenderer.containsHTML("I <3 cats"))
    }

    func testContainsHTMLIgnoresOpeningTagWithoutClose() {
        // A lone opening tag (no closing tag anywhere) is treated as plain text.
        XCTAssertFalse(RichTextRenderer.containsHTML("<br> by itself"))
    }

    // MARK: - render

    func testRenderHTMLExtractsVisibleText() {
        let result = RichTextRenderer.render("<p>Hello <strong>world</strong></p>")
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("Hello"), "Expected rendered text to contain 'Hello', got: \(plain)")
        XCTAssertTrue(plain.contains("world"), "Expected rendered text to contain 'world', got: \(plain)")
        XCTAssertFalse(plain.contains("<strong>"), "Rendered output should not contain raw tags")
    }

    func testRenderMarkdownAutolinkPreservesText() {
        let result = RichTextRenderer.render("Visit <https://example.com> today")
        let plain = String(result.characters)
        XCTAssertTrue(
            plain.contains("https://example.com"),
            "Markdown autolink should be preserved in rendered output, got: \(plain)"
        )
    }

    func testRenderPlainTextRoundTrips() {
        let source = "Just a plain description."
        let result = RichTextRenderer.render(source)
        XCTAssertEqual(String(result.characters), source)
    }

    func testRenderHTMLPreservesListItems() {
        let result = RichTextRenderer.render("<ul><li>alpha</li><li>beta</li></ul>")
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("alpha"))
        XCTAssertTrue(plain.contains("beta"))
    }
}
