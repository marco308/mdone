import SwiftUI
import XCTest
@testable import mDone

/// The layout rules behind the iPad detail pane (issue #34). The views
/// themselves are not unit tested; these pin down when the pane appears and
/// how wide it is, which is what a Split View or Stage Manager resize
/// exercises.
final class InlineTaskDetailTests: XCTestCase {
    // MARK: - showsPane

    func testCompactWidthNeverShowsPane() {
        XCTAssertFalse(InlineTaskDetailLayout.showsPane(isRegularWidth: false, containerWidth: 1366))
    }

    func testRegularWidthShowsPaneAtOrAboveMinimum() {
        let minimum = InlineTaskDetailLayout.minimumContainerWidth
        XCTAssertTrue(InlineTaskDetailLayout.showsPane(isRegularWidth: true, containerWidth: minimum))
        XCTAssertTrue(InlineTaskDetailLayout.showsPane(isRegularWidth: true, containerWidth: 1366))
    }

    func testRegularWidthBelowMinimumFallsBackToSheet() {
        let minimum = InlineTaskDetailLayout.minimumContainerWidth
        XCTAssertFalse(InlineTaskDetailLayout.showsPane(isRegularWidth: true, containerWidth: minimum - 1))
    }

    func testTypicalIPadLayoutsShowPane() {
        // 11-inch portrait, 11-inch landscape, 13-inch landscape, and a
        // two-thirds Split View on a 13-inch (about 910pt).
        for width: CGFloat in [834, 1194, 1366, 910] {
            XCTAssertTrue(
                InlineTaskDetailLayout.showsPane(isRegularWidth: true, containerWidth: width),
                "expected a pane at \(width)pt"
            )
        }
    }

    // MARK: - paneWidth

    func testPaneWidthIsClampedToMinimum() {
        // 700 * 0.42 = 294, below the floor.
        XCTAssertEqual(InlineTaskDetailLayout.paneWidth(for: 700), InlineTaskDetailLayout.minimumPaneWidth)
    }

    func testPaneWidthIsClampedToMaximum() {
        // 1366 * 0.42 = 573, above the ceiling.
        XCTAssertEqual(InlineTaskDetailLayout.paneWidth(for: 1366), InlineTaskDetailLayout.maximumPaneWidth)
    }

    func testPaneWidthScalesBetweenClamps() {
        let width = InlineTaskDetailLayout.paneWidth(for: 1000)
        XCTAssertEqual(width, 1000 * InlineTaskDetailLayout.paneFraction, accuracy: 0.001)
    }

    func testPaneLeavesTheListAtLeastAsWideAsAPhone() {
        // At the narrowest container that gets a pane, the list must still
        // have room for a phone-width row.
        let container = InlineTaskDetailLayout.minimumContainerWidth
        let list = container - InlineTaskDetailLayout.paneWidth(for: container)
        XCTAssertGreaterThanOrEqual(list, 320)
    }

    // MARK: - InlineTaskSelection

    func testSelectionStartsEmptyAndHoldsTask() {
        let selection = InlineTaskSelection()
        XCTAssertNil(selection.task)

        let task = VTask(id: 7, title: "Test", done: false, priority: 0, projectId: 1)
        selection.task = task
        XCTAssertEqual(selection.task?.id, 7)

        selection.task = nil
        XCTAssertNil(selection.task)
    }
}
