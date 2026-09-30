import SwiftData
import XCTest
@testable import mDone

/// The Focus Run queue on its own: pure value logic, both platforms.
final class FocusRunTests: XCTestCase {
    func testStartingQueuesOnlyTheTasksAfterTheChosenOne() throws {
        let run = try XCTUnwrap(FocusRun(startingAt: 2, in: [1, 2, 3, 4]))
        XCTAssertEqual(run.queue, [3, 4])
    }

    func testStartingOnATaskNotInTheListFails() {
        XCTAssertNil(FocusRun(startingAt: 9, in: [1, 2, 3]))
    }

    func testDuplicatesKeepTheirFirstPositionOnly() throws {
        // A task can show in two sections; the run should visit it once, and
        // never come back round to the task it started on.
        let run = try XCTUnwrap(FocusRun(startingAt: 1, in: [1, 2, 3, 2, 1, 4]))
        XCTAssertEqual(run.queue, [2, 3, 4])
    }

    func testCanStartNeedsSomethingAfterTheTask() {
        XCTAssertTrue(FocusRun.canStart(at: 1, in: [1, 2]))
        XCTAssertFalse(FocusRun.canStart(at: 2, in: [1, 2]))
        XCTAssertFalse(FocusRun.canStart(at: 3, in: [1, 2]))
        XCTAssertFalse(FocusRun.canStart(at: 1, in: []))
    }

    func testAdvanceReturnsNextEligibleAndDropsIneligibleOnTheWay() throws {
        var run = try XCTUnwrap(FocusRun(startingAt: 1, in: [1, 2, 3, 4]))
        let done: Set<Int64> = [2]

        XCTAssertEqual(run.peekNext { !done.contains($0) }, 3)
        XCTAssertEqual(run.remainingCount { !done.contains($0) }, 2)

        XCTAssertEqual(run.advance(completedCurrent: true) { !done.contains($0) }, 3)
        XCTAssertEqual(run.queue, [4])
        XCTAssertEqual(run.completedCount, 1)

        XCTAssertEqual(run.advance(completedCurrent: false) { !done.contains($0) }, 4)
        XCTAssertEqual(run.skippedCount, 1)

        XCTAssertNil(run.advance(completedCurrent: true) { _ in true })
        XCTAssertEqual(run.completedCount, 2)
        XCTAssertTrue(run.queue.isEmpty)
    }

    func testRoundTripsThroughCodable() throws {
        var run = try XCTUnwrap(FocusRun(startingAt: 1, in: [1, 2, 3]))
        _ = run.advance(completedCurrent: true) { _ in true }
        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded, run)
    }
}

#if os(iOS)
/// A run driven through `FocusManager`: completing the focused task brings up
/// the next one, and plain Focus still ends when its task is done.
@MainActor
final class FocusManagerRunTests: XCTestCase {
    private var container: ModelContainer!
    private var tasks: [Int64: VTask] = [:]

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([FocusRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        clearDefaults()
        tasks = [
            1: makeTask(id: 1, title: "Write report"),
            2: makeTask(id: 2, title: "Reply to Sam"),
            3: makeTask(id: 3, title: "Book dentist"),
        ]
    }

    override func tearDown() async throws {
        clearDefaults()
        container = nil
        try await super.tearDown()
    }

    func testCompletingTheFocusedTaskMovesToTheNext() async throws {
        let manager = try await startedRun(at: 1, order: [1, 2, 3])
        XCTAssertEqual(manager.runUpNext?.id, 2)
        XCTAssertEqual(manager.runRemainingCount, 2)

        complete(1, in: manager)

        XCTAssertEqual(manager.focusedTaskId, 2)
        XCTAssertEqual(manager.currentSession?.taskTitle, "Reply to Sam")
        XCTAssertTrue(manager.isRunActive)
        XCTAssertEqual(manager.runRemainingCount, 1)
        XCTAssertEqual(try fetchRecords().map(\.taskId), [1])
    }

    func testTasksFinishedElsewhereAreSkippedOver() async throws {
        let manager = try await startedRun(at: 1, order: [1, 2, 3])
        tasks[2]?.done = true

        complete(1, in: manager)

        XCTAssertEqual(manager.focusedTaskId, 3)
    }

    func testRunEndsWithASummaryWhenTheListRunsOut() async throws {
        let manager = try await startedRun(at: 1, order: [1, 2, 3])

        complete(1, in: manager)
        manager.skipToNextInRun()
        XCTAssertEqual(manager.focusedTaskId, 3)
        complete(3, in: manager)

        XCTAssertNil(manager.currentSession)
        XCTAssertFalse(manager.isRunActive)
        XCTAssertEqual(manager.finishedRun, FocusRunSummary(completedCount: 2, skippedCount: 1))
        XCTAssertNil(FocusConstants.sharedDefaults.data(forKey: FocusManager.focusRunKey))

        manager.dismissRunSummary()
        XCTAssertNil(manager.finishedRun)
    }

    func testEndingFocusEndsTheRun() async throws {
        let manager = try await startedRun(at: 1, order: [1, 2, 3])

        manager.endFocus()

        XCTAssertFalse(manager.isRunActive)
        XCTAssertNil(manager.finishedRun)
        complete(1, in: manager)
        XCTAssertNil(manager.currentSession)
    }

    func testDeletingTheFocusedTaskMovesOn() async throws {
        let manager = try await startedRun(at: 1, order: [1, 2, 3])
        tasks[1] = nil

        manager.handleTaskDeleted(taskId: 1)

        XCTAssertEqual(manager.focusedTaskId, 2)
    }

    func testPlainFocusStillEndsWhenTheTaskIsDone() throws {
        let manager = makeManager()
        manager.startFocus(task: try XCTUnwrap(tasks[1]), projectName: "Work")

        complete(1, in: manager)

        XCTAssertNil(manager.currentSession)
        XCTAssertFalse(manager.isRunActive)
        XCTAssertNil(manager.finishedRun)
    }

    func testRunIsRestoredAlongsideItsSession() async throws {
        _ = try await startedRun(at: 1, order: [1, 2, 3])

        let relaunched = makeManager()

        XCTAssertEqual(relaunched.focusedTaskId, 1)
        XCTAssertTrue(relaunched.isRunActive)
        XCTAssertEqual(relaunched.runUpNext?.id, 2)
    }

    func testOrphanedRunIsDroppedWithoutASession() throws {
        let orphan = try XCTUnwrap(FocusRun(startingAt: 1, in: [1, 2]))
        FocusConstants.sharedDefaults.set(try JSONEncoder().encode(orphan), forKey: FocusManager.focusRunKey)

        let manager = makeManager()

        XCTAssertFalse(manager.isRunActive)
        XCTAssertNil(FocusConstants.sharedDefaults.data(forKey: FocusManager.focusRunKey))
    }

    // MARK: - Helpers

    private func makeManager() -> FocusManager {
        let manager = FocusManager(modelContainer: container, liveActivitiesEnabled: false)
        manager.taskLookup = { [unowned self] id in
            tasks[id].map { ($0, "Work") }
        }
        return manager
    }

    /// Starts a run with nothing focused beforehand, which starts the first
    /// session straight away.
    private func startedRun(at taskId: Int64, order: [Int64]) async throws -> FocusManager {
        let manager = makeManager()
        manager.startFocusRun(task: try XCTUnwrap(tasks[taskId]), projectName: "Work", order: order)
        XCTAssertEqual(manager.focusedTaskId, taskId)
        XCTAssertTrue(manager.isRunActive)
        // Backdate so the session is long enough to be recorded.
        manager.currentSession = FocusSession(
            taskId: taskId,
            taskTitle: tasks[taskId]?.title ?? "",
            projectName: "Work",
            priorityLevel: 0,
            sessionStartDate: Date().addingTimeInterval(-120),
            focusIntervalStartDate: Date().addingTimeInterval(-120),
            elapsedBeforePause: 0,
            isPaused: false
        )
        return manager
    }

    /// What `AppState.toggleTaskDone` does from the manager's point of view:
    /// the live copy is marked done, then the completion hook fires.
    private func complete(_ taskId: Int64, in manager: FocusManager) {
        tasks[taskId]?.done = true
        manager.handleTaskCompleted(taskId: taskId)
    }

    private func makeTask(id: Int64, title: String) -> VTask {
        VTask(id: id, title: title, done: false, priority: 0, projectId: 1)
    }

    private func fetchRecords() throws -> [FocusRecord] {
        let descriptor = FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.startedAt)])
        return try container.mainContext.fetch(descriptor)
    }

    private func clearDefaults() {
        FocusConstants.sharedDefaults.removeObject(forKey: FocusConstants.focusSessionKey)
        FocusConstants.sharedDefaults.removeObject(forKey: FocusManager.focusRunKey)
    }
}
#endif
