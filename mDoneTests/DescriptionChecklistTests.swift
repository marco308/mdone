import XCTest
@testable import mDone

final class DescriptionChecklistTests: XCTestCase {
    /// Exactly what Vikunja's Tiptap editor writes for the screenshot in
    /// issue #200: two ticked names and one still open.
    private let vikunjaHTML = """
    <ul data-type="taskList"><li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Johnny</p></div></li><li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Steven</p></div></li><li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span></label><div><p>Atlas</p></div></li></ul>
    """

    // MARK: - parse

    func testParseReadsVikunjaTaskList() throws {
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(vikunjaHTML))
        XCTAssertEqual(checklist.items.map(\.text), ["Johnny", "Steven", "Atlas"])
        XCTAssertEqual(checklist.items.map(\.isChecked), [true, true, false])
        XCTAssertEqual(checklist.items.map(\.id), [0, 1, 2])
        XCTAssertEqual(checklist.doneCount, 2)
        XCTAssertEqual(checklist.totalCount, 3)
        XCTAssertFalse(checklist.isComplete)
        XCTAssertEqual(checklist.fraction, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testParseReturnsNilWithoutChecklist() {
        XCTAssertNil(DescriptionChecklist.parse(nil))
        XCTAssertNil(DescriptionChecklist.parse(""))
        XCTAssertNil(DescriptionChecklist.parse("<p>Plain description</p>"))
        XCTAssertNil(DescriptionChecklist.parse("<ul><li>Ordinary bullet</li></ul>"))
        XCTAssertNil(DescriptionChecklist.parse("- [ ] markdown checkbox is not a Tiptap task item"))
    }

    func testParseAcceptsAnyAttributeOrder() throws {
        let html = #"<ul data-type="taskList"><li data-type="taskItem" data-checked="false"><p>Only</p></li></ul>"#
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(html))
        XCTAssertEqual(checklist.items.count, 1)
        XCTAssertEqual(checklist.items[0].text, "Only")
        XCTAssertFalse(checklist.items[0].isChecked)
    }

    func testParseStripsInlineMarkupAndDecodesEntities() throws {
        let html = #"<ul data-type="taskList"><li data-checked="false"><div><p>Pay <strong>Tom &amp; Jerry</strong>&nbsp;&lt;today&gt;</p></div></li></ul>"#
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(html))
        XCTAssertEqual(checklist.items[0].text, "Pay Tom & Jerry <today>")
    }

    func testParseFlattensNestedItems() throws {
        let html = """
        <ul data-type="taskList"><li data-checked="false"><p>Parent</p><ul data-type="taskList"><li data-checked="true"><p>Child</p></li></ul></li></ul>
        """
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(html))
        XCTAssertEqual(checklist.items.map(\.text), ["Parent", "Child"])
        XCTAssertEqual(checklist.items.map(\.isChecked), [false, true])
    }

    func testParseIsCompleteWhenEveryItemIsChecked() throws {
        let html = #"<ul data-type="taskList"><li data-checked="true"><p>A</p></li><li data-checked="true"><p>B</p></li></ul>"#
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(html))
        XCTAssertTrue(checklist.isComplete)
        XCTAssertEqual(checklist.fraction, 1)
    }

    // MARK: - toggling

    func testTogglingTicksAnOpenItem() throws {
        let updated = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 2, in: vikunjaHTML))
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(updated))
        XCTAssertEqual(checklist.items.map(\.isChecked), [true, true, true])
        // The input is kept in step with the li so the markup stays the shape the web app writes.
        XCTAssertTrue(
            updated
                .contains(
                    #"<li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Atlas</p></div></li>"#
                ),
            updated
        )
    }

    func testTogglingUnticksACheckedItem() throws {
        let updated = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 0, in: vikunjaHTML))
        let checklist = try XCTUnwrap(DescriptionChecklist.parse(updated))
        XCTAssertEqual(checklist.items.map(\.isChecked), [false, true, false])
        XCTAssertTrue(
            updated
                .contains(
                    #"<li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span></label><div><p>Johnny</p></div></li>"#
                ),
            updated
        )
    }

    func testTogglingLeavesEverythingElseUntouched() throws {
        let html = "<p>Before &amp; after</p>\n" + vikunjaHTML + "\n<p>Tail with <em>emphasis</em></p>"
        let updated = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 2, in: html))
        XCTAssertTrue(updated.hasPrefix("<p>Before &amp; after</p>\n"))
        XCTAssertTrue(updated.hasSuffix("\n<p>Tail with <em>emphasis</em></p>"))
        // Toggling back restores the exact original bytes.
        XCTAssertEqual(DescriptionChecklist.toggling(itemAt: 2, in: updated), html)
    }

    func testTogglingHandlesBareCheckedAttributeAndSelfClosingInput() throws {
        let html = #"<ul data-type="taskList"><li data-checked="true"><label><input checked type="checkbox" /></label><p>X</p></li></ul>"#
        let updated = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 0, in: html))
        XCTAssertEqual(
            updated,
            #"<ul data-type="taskList"><li data-checked="false"><label><input type="checkbox" /></label><p>X</p></li></ul>"#
        )
        let reticked = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 0, in: updated))
        XCTAssertEqual(
            reticked,
            #"<ul data-type="taskList"><li data-checked="true"><label><input type="checkbox" checked="checked" /></label><p>X</p></li></ul>"#
        )
    }

    func testTogglingOnlyTouchesTheChosenItemsCheckbox() throws {
        // Each item's checkbox lives in its own body, so ticking the second item must not tick the first's input.
        let html = #"<ul data-type="taskList"><li data-checked="false"><input type="checkbox"><p>A</p></li><li data-checked="false"><input type="checkbox"><p>B</p></li></ul>"#
        let updated = try XCTUnwrap(DescriptionChecklist.toggling(itemAt: 1, in: html))
        XCTAssertEqual(
            updated,
            #"<ul data-type="taskList"><li data-checked="false"><input type="checkbox"><p>A</p></li><li data-checked="true"><input type="checkbox" checked="checked"><p>B</p></li></ul>"#
        )
    }

    func testTogglingOutOfRangeReturnsNil() {
        XCTAssertNil(DescriptionChecklist.toggling(itemAt: 3, in: vikunjaHTML))
        XCTAssertNil(DescriptionChecklist.toggling(itemAt: 0, in: "<p>nothing</p>"))
    }

    func testSettingToTheCurrentStateIsANoOp() {
        XCTAssertEqual(DescriptionChecklist.setting(itemAt: 0, checked: true, in: vikunjaHTML), vikunjaHTML)
        XCTAssertNil(DescriptionChecklist.setting(itemAt: 9, checked: true, in: vikunjaHTML))
    }

    // MARK: - segments

    func testSegmentsSplitProseAroundTheChecklist() {
        let html = "<p>Chase these:</p>" + vikunjaHTML + "<p>Then pay.</p>"
        let segments = DescriptionChecklist.segments(of: html)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .html("<p>Chase these:</p>"))
        guard case let .checklist(items) = segments[1]
        else { return XCTFail("Expected a checklist, got \(segments[1])") }
        XCTAssertEqual(items.map(\.id), [0, 1, 2])
        XCTAssertEqual(items.map(\.text), ["Johnny", "Steven", "Atlas"])
        XCTAssertEqual(segments[2], .html("<p>Then pay.</p>"))
    }

    func testSegmentsKeepDocumentOrderIdsAcrossTwoLists() {
        let first = #"<ul data-type="taskList"><li data-checked="false"><p>A</p></li></ul>"#
        let second = #"<ul data-type="taskList"><li data-checked="true"><p>B</p></li><li data-checked="false"><p>C</p></li></ul>"#
        let segments = DescriptionChecklist.segments(of: first + "<p>gap</p>" + second)
        XCTAssertEqual(segments.count, 3)
        guard case let .checklist(firstItems) = segments[0],
              case let .checklist(secondItems) = segments[2]
        else { return XCTFail("Expected checklists at both ends, got \(segments)") }
        XCTAssertEqual(firstItems.map(\.id), [0])
        XCTAssertEqual(secondItems.map(\.id), [1, 2])
        XCTAssertEqual(secondItems.map(\.text), ["B", "C"])
    }

    func testSegmentsTreatANestedListAsOneChecklist() {
        let html = """
        <ul data-type="taskList"><li data-checked="false"><p>Parent</p><ul data-type="taskList"><li data-checked="true"><p>Child</p></li></ul></li></ul><p>after</p>
        """
        let segments = DescriptionChecklist.segments(of: html)
        XCTAssertEqual(segments.count, 2)
        guard case let .checklist(items) = segments[0]
        else { return XCTFail("Expected a checklist, got \(segments[0])") }
        XCTAssertEqual(items.map(\.text), ["Parent", "Child"])
        XCTAssertEqual(segments[1], .html("<p>after</p>"))
    }

    func testSegmentsWithoutChecklistIsTheWholeDescription() {
        XCTAssertEqual(DescriptionChecklist.segments(of: "<p>Plain</p>"), [.html("<p>Plain</p>")])
        XCTAssertEqual(DescriptionChecklist.segments(of: "Just text"), [.html("Just text")])
    }

    // MARK: - VTask

    func testTaskChecklistCounts() {
        var task = VTask(id: 1, title: "Bills", description: vikunjaHTML, done: false, priority: 0, projectId: 1)
        XCTAssertEqual(task.checklistCounts?.done, 2)
        XCTAssertEqual(task.checklistCounts?.total, 3)
        task.description = "<p>No list</p>"
        XCTAssertNil(task.checklistCounts)
        task.description = nil
        XCTAssertNil(task.checklistCounts)
    }
}
