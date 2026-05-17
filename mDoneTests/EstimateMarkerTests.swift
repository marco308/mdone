import XCTest
@testable import mDone

final class EstimateMarkerTests: XCTestCase {
    // MARK: - parse

    func testParseReturnsNilForNilOrEmpty() {
        XCTAssertNil(EstimateMarker.parse(nil))
        XCTAssertNil(EstimateMarker.parse(""))
    }

    func testParseReturnsNilWhenNoMarker() {
        XCTAssertNil(EstimateMarker.parse("Plain old description with no marker."))
    }

    func testParseReturnsSecondsForBareMarker() {
        XCTAssertEqual(EstimateMarker.parse("<!-- mdone:estimate=1500 -->"), 1500)
    }

    func testParseReturnsSecondsWhenAppendedToBody() {
        let input = "Read the spec.\n\n<!-- mdone:estimate=900 -->"
        XCTAssertEqual(EstimateMarker.parse(input), 900)
    }

    func testParseToleratesWhitespaceInsideComment() {
        XCTAssertEqual(EstimateMarker.parse("<!--   mdone:estimate=42   -->"), 42)
    }

    func testParseTakesFirstMatchIfMultiplePresent() {
        let input = "Body. <!-- mdone:estimate=100 --> tail <!-- mdone:estimate=999 -->"
        XCTAssertEqual(EstimateMarker.parse(input), 100)
    }

    func testParseRejectsZeroAndMalformed() {
        XCTAssertNil(EstimateMarker.parse("<!-- mdone:estimate=0 -->"))
        XCTAssertNil(EstimateMarker.parse("<!-- mdone:estimate=-30 -->"))
        XCTAssertNil(EstimateMarker.parse("<!-- mdone:estimate=abc -->"))
        XCTAssertNil(EstimateMarker.parse("<!-- mdone:est=30 -->"))
    }

    // MARK: - strip

    func testStripReturnsNilForNilEmptyOrWhitespace() {
        XCTAssertNil(EstimateMarker.strip(nil))
        XCTAssertNil(EstimateMarker.strip(""))
        XCTAssertNil(EstimateMarker.strip("   \n  "))
    }

    func testStripPreservesBodyWhenNoMarker() {
        XCTAssertEqual(EstimateMarker.strip("Just the body."), "Just the body.")
    }

    func testStripRemovesMarkerAndTrimsTrailingWhitespace() {
        let input = "Body line.\n\n<!-- mdone:estimate=600 -->"
        XCTAssertEqual(EstimateMarker.strip(input), "Body line.")
    }

    func testStripRemovesAllMarkersIfMultiple() {
        let input = "Body.\n<!-- mdone:estimate=60 --> more text <!-- mdone:estimate=120 -->"
        let stripped = EstimateMarker.strip(input) ?? ""
        XCTAssertFalse(stripped.contains("mdone:estimate"))
        XCTAssertTrue(stripped.contains("Body."))
        XCTAssertTrue(stripped.contains("more text"))
    }

    func testStripReturnsNilForMarkerOnlyDescription() {
        XCTAssertNil(EstimateMarker.strip("<!-- mdone:estimate=300 -->"))
    }

    func testStripPreservesLeadingWhitespaceWhenNoMarker() {
        // User-intentional leading whitespace (indentation, a blank line
        // they typed deliberately) must survive a no-marker strip — earlier
        // versions of `strip` trimmed both ends and silently rewrote bodies.
        XCTAssertEqual(EstimateMarker.strip("  hello"), "  hello")
        XCTAssertEqual(EstimateMarker.strip("\n\nhello"), "\n\nhello")
    }

    func testStripDoesNotConcatenateWordsAroundInlineMarker() {
        // An agent that drops the marker mid-body must not cause `strip` to
        // glue the adjacent words together — replacement inserts a single
        // space so word boundaries survive.
        let input = "foo <!-- mdone:estimate=600 --> bar"
        let stripped = EstimateMarker.strip(input) ?? ""
        XCTAssertFalse(stripped.contains("foobar"), "Inline marker removal must not concatenate words")
        XCTAssertTrue(stripped.contains("foo") && stripped.contains("bar"))
    }

    // MARK: - apply

    func testApplyWithNilEstimateAndNilBodyReturnsNil() {
        XCTAssertNil(EstimateMarker.apply(nil, to: nil))
    }

    func testApplyWithNilEstimateStripsAnyExistingMarker() {
        XCTAssertEqual(
            EstimateMarker.apply(nil, to: "Body.\n\n<!-- mdone:estimate=600 -->"),
            "Body."
        )
    }

    func testApplyWithNonPositiveEstimateBehavesLikeClear() {
        XCTAssertEqual(EstimateMarker.apply(0, to: "Body."), "Body.")
        XCTAssertEqual(EstimateMarker.apply(-5, to: "Body."), "Body.")
    }

    func testApplyAppendsMarkerToBodyWithBlankLine() {
        XCTAssertEqual(
            EstimateMarker.apply(1800, to: "Plan the week."),
            "Plan the week.\n\n<!-- mdone:estimate=1800 -->"
        )
    }

    func testApplyEmitsBareMarkerWhenBodyIsEmpty() {
        XCTAssertEqual(EstimateMarker.apply(1800, to: nil), "<!-- mdone:estimate=1800 -->")
        XCTAssertEqual(EstimateMarker.apply(1800, to: ""), "<!-- mdone:estimate=1800 -->")
    }

    func testApplyIsIdempotentWhenCalledTwice() {
        let once = EstimateMarker.apply(1500, to: "Body.")
        let twice = EstimateMarker.apply(1500, to: once)
        XCTAssertEqual(once, twice)
    }

    func testApplyReplacesExistingMarker() {
        let input = "Body.\n\n<!-- mdone:estimate=600 -->"
        XCTAssertEqual(
            EstimateMarker.apply(1500, to: input),
            "Body.\n\n<!-- mdone:estimate=1500 -->"
        )
    }

    func testApplyRoundsFractionalSecondsToNearestInteger() {
        XCTAssertEqual(EstimateMarker.apply(60.6, to: nil), "<!-- mdone:estimate=61 -->")
    }

    func testApplyClampsTinyPositiveSoMarkerStillParses() {
        // Without clamping, Int(0.4.rounded()) == 0, which would emit
        // `mdone:estimate=0` — and `parse` rejects non-positive seconds,
        // breaking the round-trip.
        let out = EstimateMarker.apply(0.4, to: nil)
        XCTAssertEqual(out, "<!-- mdone:estimate=1 -->")
        XCTAssertEqual(EstimateMarker.parse(out), 1)
    }

    // MARK: - round-trip via VTask

    func testRoundTripViaVTaskComputedAccessors() {
        let composed = EstimateMarker.apply(2400, to: "Plan Q3.")
        let task = makeTask(description: composed)
        XCTAssertEqual(task.estimatedSeconds, 2400)
        XCTAssertEqual(task.userVisibleDescription, "Plan Q3.")
    }

    func testVTaskAccessorsHandleNoMarker() {
        let task = makeTask(description: "Just a body.")
        XCTAssertNil(task.estimatedSeconds)
        XCTAssertEqual(task.userVisibleDescription, "Just a body.")
    }

    func testVTaskAccessorsHandleMarkerOnly() {
        let task = makeTask(description: "<!-- mdone:estimate=900 -->")
        XCTAssertEqual(task.estimatedSeconds, 900)
        XCTAssertNil(task.userVisibleDescription)
    }

    private func makeTask(description: String?) -> VTask {
        VTask(
            id: 1,
            title: "T",
            description: description,
            done: false,
            doneAt: nil,
            dueDate: nil,
            startDate: nil,
            endDate: nil,
            priority: 0,
            projectId: 1,
            hexColor: nil,
            percentDone: nil,
            uid: nil,
            position: nil,
            isFavorite: nil,
            repeatAfter: nil,
            repeatMode: nil,
            identifier: nil,
            index: nil,
            reminders: nil,
            assignees: nil,
            labels: nil,
            createdBy: nil,
            created: nil,
            updated: nil,
            bucketId: nil,
            coverImageAttachmentId: nil
        )
    }
}
