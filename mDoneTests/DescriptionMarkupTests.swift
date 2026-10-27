import XCTest
@testable import mDone

/// Editing a web-app description as formatted text (#277).
final class DescriptionMarkupTests: XCTestCase {
    /// A checklist exactly as Vikunja's Tiptap editor writes it.
    private let tiptapChecklist = """
    <ul data-type="taskList"><li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Johnny</p></div></li><li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span></label><div><p>Atlas</p></div></li></ul>
    """

    private func editable(_ html: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(DescriptionMarkup.editableText(fromHTML: html), file: file, line: line)
    }

    /// HTML in the canonical shape survives HTML -> text -> HTML unchanged.
    private func assertRoundTrip(_ html: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try editable(html, file: file, line: line)
        XCTAssertEqual(DescriptionMarkup.html(fromEditableText: text), html, file: file, line: line)
    }

    // MARK: - HTML to text

    func testParagraphsAndInlineFormatting() throws {
        let html = "<p>Hello <strong>bold</strong> and <em>italic</em></p><p>Second</p>"
        XCTAssertEqual(try editable(html), "Hello **bold** and *italic*\n\nSecond")
        try assertRoundTrip(html)
    }

    func testLineBreakInsideParagraph() throws {
        let html = "<p>one<br>two</p>"
        XCTAssertEqual(try editable(html), "one\ntwo")
        try assertRoundTrip(html)
    }

    func testLinks() throws {
        let html = #"<p>See <a target="_blank" rel="noopener noreferrer nofollow" href="https://example.com/a">the docs</a></p>"#
        XCTAssertEqual(try editable(html), "See [the docs](https://example.com/a)")
        XCTAssertEqual(
            try DescriptionMarkup.html(fromEditableText: editable(html)),
            #"<p>See <a href="https://example.com/a">the docs</a></p>"#
        )
    }

    func testLinkWhoseTextIsItsAddressStaysBare() throws {
        let html = #"<p>Go to <a href="https://example.com/x">https://example.com/x</a>.</p>"#
        XCTAssertEqual(try editable(html), "Go to https://example.com/x.")
        try assertRoundTrip(html)
    }

    func testBulletAndNumberedLists() throws {
        let bullets = "<ul><li><p>milk</p></li><li><p><strong>eggs</strong></p></li></ul>"
        XCTAssertEqual(try editable(bullets), "- milk\n- **eggs**")
        try assertRoundTrip(bullets)

        let numbered = "<ol><li><p>first</p></li><li><p>second</p></li></ol>"
        XCTAssertEqual(try editable(numbered), "1. first\n2. second")
        try assertRoundTrip(numbered)

        let started = #"<ol start="3"><li><p>third</p></li></ol>"#
        XCTAssertEqual(try editable(started), "3. third")
        try assertRoundTrip(started)
    }

    func testListItemsWithoutParagraphs() throws {
        XCTAssertEqual(try editable("<ul><li>bare</li></ul>"), "- bare")
    }

    func testChecklistKeepsCheckedState() throws {
        let text = try editable(tiptapChecklist)
        XCTAssertEqual(text, "- [x] Johnny\n- [ ] Atlas")
        try assertRoundTrip(tiptapChecklist)

        let saved = DescriptionMarkup.html(fromEditableText: text)
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(saved))
        XCTAssertEqual(checklist.items.map(\.text), ["Johnny", "Atlas"])
        XCTAssertEqual(checklist.items.map(\.isChecked), [true, false])
    }

    func testTypedChecklistBecomesTiptapTaskList() throws {
        let html = DescriptionMarkup.html(fromEditableText: "Shopping\n\n- [ ] bread\n- [X] jam")
        XCTAssertEqual(html, """
        <p>Shopping</p><ul data-type="taskList"><li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span></label><div><p>bread</p></div></li><li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>jam</p></div></li></ul>
        """)
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(html))
        XCTAssertEqual(checklist.items.map(\.isChecked), [false, true])
        // Ticking it in mDone still works on the markup this writes.
        let toggled = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 0, in: html))
        XCTAssertEqual(DescriptionChecklist.parse(toggled)?.items.map(\.isChecked), [true, true])
    }

    func testHeadings() throws {
        let html = "<h2>Plan</h2><p>Body</p>"
        XCTAssertEqual(try editable(html), "## Plan\n\nBody")
        try assertRoundTrip(html)
    }

    func testEmptyParagraphsBetweenBlocksSurvive() throws {
        let html = "<p>a</p><p></p><p>b</p>"
        XCTAssertEqual(try editable(html), "a\n\n\nb")
        try assertRoundTrip(html)
        // Leading and trailing empty paragraphs carry nothing.
        XCTAssertEqual(try editable("<p></p><p>a</p><p></p>"), "a")
    }

    func testEntitiesDecodeAndReEncode() throws {
        let html = "<p>Fish &amp; chips &lt;3 &#39;yes&#39;</p>"
        XCTAssertEqual(try editable(html), "Fish & chips <3 'yes'")
        XCTAssertEqual(
            try DescriptionMarkup.html(fromEditableText: editable(html)),
            "<p>Fish &amp; chips &lt;3 'yes'</p>"
        )
    }

    func testTextThatLooksLikeMarkupIsEscaped() throws {
        let html = "<p>- not a list</p><p>1. not numbered</p><p># not a heading</p><p>2 * 3 [x] a\\b</p>"
        let text = try editable(html)
        XCTAssertEqual(text, "\\- not a list\n\n1\\. not numbered\n\n\\# not a heading\n\n2 \\* 3 \\[x\\] a\\\\b")
        try assertRoundTrip(html)
    }

    func testNestedFormatting() throws {
        try assertRoundTrip("<p><strong><em>both</em></strong> and <em>it <strong>bold</strong> it</em></p>")
        try assertRoundTrip(#"<p><a href="https://example.com">a <strong>bold</strong> link</a></p>"#)
    }

    // MARK: - Unsupported markup

    func testUnsupportedMarkupReturnsNil() {
        let unsupported = [
            "<table><tr><td>x</td></tr></table>",
            #"<p>an <img src="a.png"> image</p>"#,
            "<pre><code>let x = 1</code></pre>",
            "<blockquote><p>quote</p></blockquote>",
            "<p>some <code>code</code></p>",
            "<p><u>underlined</u></p>",
            "<ul><li><p>parent</p><ul><li><p>child</p></li></ul></li></ul>",
            "<ul><li><p>one</p><p>two</p></li></ul>",
            "<p>a</p><!-- a comment -->",
            "<p>unclosed",
            "loose text <strong>outside</strong> a paragraph",
        ]
        for html in unsupported {
            XCTAssertNil(DescriptionMarkup.editableText(fromHTML: html), html)
        }
    }

    // MARK: - Text to HTML

    func testTypedMarkupToHTML() {
        XCTAssertEqual(
            DescriptionMarkup.html(fromEditableText: "Intro line\nnext line\n\n- a\n- b\n\n1. x\n2. y"),
            "<p>Intro line<br>next line</p><ul><li><p>a</p></li><li><p>b</p></li></ul><ol><li><p>x</p></li><li><p>y</p></li></ol>"
        )
        XCTAssertEqual(
            DescriptionMarkup.html(fromEditableText: "Visit https://example.com, now"),
            #"<p>Visit <a href="https://example.com">https://example.com</a>, now</p>"#
        )
        XCTAssertEqual(DescriptionMarkup.html(fromEditableText: "a <b> & c"), "<p>a &lt;b&gt; &amp; c</p>")
        XCTAssertEqual(
            DescriptionMarkup.html(fromEditableText: "lone * star and **unclosed"),
            "<p>lone * star and **unclosed</p>"
        )
        XCTAssertEqual(DescriptionMarkup.html(fromEditableText: ""), "")
    }

    // MARK: - Edit session

    func testPlainTextDescriptionIsEditedUnchanged() {
        var session = DescriptionEditSession(stored: "Buy milk\n- [ ] not converted")
        XCTAssertEqual(session.mode, .plainText)
        XCTAssertEqual(session.text, "Buy milk\n- [ ] not converted")
        session.text += "\nmore"
        XCTAssertEqual(session.storedDescription, "Buy milk\n- [ ] not converted\nmore")
    }

    func testWebDescriptionIsEditedAsFormattedText() {
        var session = DescriptionEditSession(stored: "<p>Hello <strong>world</strong></p>" + tiptapChecklist)
        XCTAssertEqual(session.mode, .formatted)
        XCTAssertEqual(session.text, "Hello **world**\n\n- [x] Johnny\n- [ ] Atlas")
        session.text = "Hello **world**\n\n- [x] Johnny\n- [x] Atlas"
        XCTAssertEqual(DescriptionChecklist.parse(session.storedDescription)?.doneCount, 2)
        XCTAssertTrue(session.storedDescription
            .hasPrefix("<p>Hello <strong>world</strong></p><ul data-type=\"taskList\">"))
    }

    func testUntouchedEditKeepsOriginalMarkupByteForByte() {
        let stored = #"<p>See <a target="_blank" href="https://example.com">docs</a></p>"#
        let session = DescriptionEditSession(stored: stored)
        XCTAssertEqual(session.mode, .formatted)
        XCTAssertEqual(session.storedDescription, stored)
    }

    func testUnsupportedDescriptionFallsBackToRawHTML() {
        let stored = "<p>Intro</p><table><tr><td>cell</td></tr></table>"
        var session = DescriptionEditSession(stored: stored)
        XCTAssertEqual(session.mode, .rawHTML)
        XCTAssertEqual(session.text, stored)
        session.text = stored + "<p>more</p>"
        XCTAssertEqual(session.storedDescription, stored + "<p>more</p>")
    }

    func testClearingFormattedDescriptionStoresEmpty() {
        var session = DescriptionEditSession(stored: "<p>gone</p>")
        session.text = ""
        XCTAssertEqual(session.storedDescription, "")
    }

    func testEstimateMarkerStillRoundTrips() throws {
        let stored = "<p>Body</p>\n\n<!-- mdone:estimate=900 -->"
        var session = DescriptionEditSession(stored: EstimateMarker.strip(stored) ?? "")
        XCTAssertEqual(session.mode, .formatted)
        XCTAssertEqual(session.text, "Body")
        session.text = "Body **edited**"
        let composed = try XCTUnwrap(EstimateMarker.apply(EstimateMarker.parse(stored), to: session.storedDescription))
        XCTAssertEqual(composed, "<p>Body <strong>edited</strong></p>\n\n<!-- mdone:estimate=900 -->")
        XCTAssertEqual(EstimateMarker.parse(composed), 900)
    }
}
