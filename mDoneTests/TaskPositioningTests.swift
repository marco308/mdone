import XCTest
@testable import mDone

/// `TaskPositioning` turns a drag into the `position` Vikunja needs. The
/// rules mirror the web app's `calculateItemPosition`, so these pin the same
/// numbers the web app would send for the same drop.
final class TaskPositioningTests: XCTestCase {
    private func task(_ id: Int64, position: Double?) -> VTask {
        var task = VTask(id: id, title: "Task \(id)", done: false, priority: 0, projectId: 1)
        task.position = position
        return task
    }

    // MARK: - position(between:and:)

    func testMidpointBetweenNeighbours() {
        XCTAssertEqual(TaskPositioning.position(between: 100, and: 200), 150)
    }

    func testTopOfListIsHalfTheFirstPosition() {
        XCTAssertEqual(TaskPositioning.position(between: nil, and: 200), 100)
    }

    func testBottomOfListLeavesTheEndGap() {
        XCTAssertEqual(TaskPositioning.position(between: 100, and: nil), 100 + 65536)
    }

    func testEmptyListIsZero() {
        XCTAssertEqual(TaskPositioning.position(between: nil, and: nil), 0)
    }

    func testTiedNeighboursNudgeAboveTheLowerOne() {
        XCTAssertEqual(TaskPositioning.position(between: 100, and: 100), 100.01)
    }

    // MARK: - move(_:fromOffsets:toOffset:)

    func testMoveDownLandsBetweenTheNewNeighbours() throws {
        let tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300), task(4, position: 400)]

        // SwiftUI reports "drop after row 3" as destination 3 (pre-move indexing).
        let move = try XCTUnwrap(TaskPositioning.move(tasks, fromOffsets: [0], toOffset: 3))

        XCTAssertEqual(move.task.id, 1)
        XCTAssertEqual(move.reordered.map(\.id), [2, 3, 1, 4])
        XCTAssertEqual(move.position, 350)
    }

    func testMoveUpLandsBetweenTheNewNeighbours() throws {
        let tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300)]

        let move = try XCTUnwrap(TaskPositioning.move(tasks, fromOffsets: [2], toOffset: 1))

        XCTAssertEqual(move.task.id, 3)
        XCTAssertEqual(move.reordered.map(\.id), [1, 3, 2])
        XCTAssertEqual(move.position, 150)
    }

    func testMoveToTopHalvesTheFirstPosition() throws {
        let tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300)]

        let move = try XCTUnwrap(TaskPositioning.move(tasks, fromOffsets: [2], toOffset: 0))

        XCTAssertEqual(move.reordered.map(\.id), [3, 1, 2])
        XCTAssertEqual(move.position, 50)
    }

    func testMoveToBottomAddsTheEndGap() throws {
        let tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300)]

        let move = try XCTUnwrap(TaskPositioning.move(tasks, fromOffsets: [0], toOffset: 3))

        XCTAssertEqual(move.reordered.map(\.id), [2, 3, 1])
        XCTAssertEqual(move.position, 300 + 65536)
    }

    func testDropInPlaceIsNoMove() {
        let tasks = [task(1, position: 100), task(2, position: 200)]
        XCTAssertNil(TaskPositioning.move(tasks, fromOffsets: [0], toOffset: 0))
        XCTAssertNil(TaskPositioning.move(tasks, fromOffsets: [0], toOffset: 1), "dropping just below itself")
    }

    func testMultiRowSelectionIsIgnored() {
        let tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300)]
        XCTAssertNil(TaskPositioning.move(tasks, fromOffsets: [0, 1], toOffset: 3))
    }

    func testOutOfRangeSourceIsIgnored() {
        XCTAssertNil(TaskPositioning.move([task(1, position: 100)], fromOffsets: [4], toOffset: 0))
    }

    /// A neighbour never fetched through a view has no position, which the
    /// server would report as 0. Treat it that way rather than crashing or
    /// inventing an index-based number.
    func testMissingNeighbourPositionCountsAsZero() throws {
        let tasks = [task(1, position: nil), task(2, position: 200)]

        let move = try XCTUnwrap(TaskPositioning.move(tasks, fromOffsets: [1], toOffset: 0))

        // Landed at the top with task 1 (position 0) below: 0 / 2.
        XCTAssertEqual(move.position, 0)
    }

    // MARK: - position(forInserting:at:into:)

    func testInsertIntoEmptyColumnIsZero() {
        XCTAssertEqual(TaskPositioning.position(forInserting: task(9, position: nil), at: 0, into: []), 0)
    }

    func testInsertAtTopOfColumn() {
        let column = [task(1, position: 100), task(2, position: 200)]
        XCTAssertEqual(TaskPositioning.position(forInserting: task(9, position: nil), at: 0, into: column), 50)
    }

    func testInsertBetweenCards() {
        let column = [task(1, position: 100), task(2, position: 200)]
        XCTAssertEqual(TaskPositioning.position(forInserting: task(9, position: nil), at: 1, into: column), 150)
    }

    func testInsertPastTheEndAppends() {
        let column = [task(1, position: 100), task(2, position: 200)]
        XCTAssertEqual(
            TaskPositioning.position(forInserting: task(9, position: nil), at: 99, into: column),
            200 + 65536
        )
    }

    /// The column passed in may still hold the card being moved (same-column
    /// drag); it must not count as its own neighbour.
    func testInsertIgnoresTheMovedCardAlreadyInTheColumn() {
        let moving = task(2, position: 200)
        let column = [task(1, position: 100), moving, task(3, position: 300)]
        XCTAssertEqual(TaskPositioning.position(forInserting: moving, at: 0, into: column), 50)
        XCTAssertEqual(TaskPositioning.position(forInserting: moving, at: 2, into: column), 300 + 65536)
    }
}
