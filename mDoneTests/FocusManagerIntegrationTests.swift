#if os(iOS)
import SwiftData
import XCTest
@testable import mDone

/// End-to-end tests for the four session-end paths and the stale-session
/// restore branch. These tests bypass `startFocus` (which would touch
/// ActivityKit / UIImpactFeedbackGenerator) by injecting `currentSession`
/// directly — the goal is to verify the persistence call sites, not
/// ActivityKit.
@MainActor
final class FocusManagerIntegrationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([FocusRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        // Clear any stale session left in shared defaults from a previous test run.
        FocusConstants.sharedDefaults.removeObject(forKey: FocusConstants.focusSessionKey)
    }

    override func tearDown() async throws {
        FocusConstants.sharedDefaults.removeObject(forKey: FocusConstants.focusSessionKey)
        container = nil
        try await super.tearDown()
    }

    // MARK: - endFocus

    func testEndFocusPersistsActiveSession() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date().addingTimeInterval(-600) // 10 min ago
        manager.currentSession = makeSession(
            taskId: 42,
            title: "Write report",
            project: "Work",
            priority: 3,
            sessionStartDate: start,
            focusIntervalStartDate: start,
            elapsedBeforePause: 0,
            isPaused: false
        )

        manager.endFocus()

        let records = try fetchRecords()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.taskId, 42)
        XCTAssertEqual(record.taskTitle, "Write report")
        XCTAssertEqual(record.projectName, "Work")
        XCTAssertEqual(record.priorityLevel, 3)
        XCTAssertEqual(record.focusedSeconds, 600, accuracy: 2)
        XCTAssertNil(manager.currentSession)
    }

    func testEndFocusWithoutActiveSessionIsNoOp() throws {
        let manager = FocusManager(modelContainer: container)
        XCTAssertNil(manager.currentSession)

        manager.endFocus()

        XCTAssertEqual(try fetchRecords().count, 0)
    }

    // MARK: - switchFocus

    func testSwitchFocusPersistsOutgoingSessionBeforeSwitching() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date().addingTimeInterval(-300) // 5 min ago
        manager.currentSession = makeSession(
            taskId: 1,
            title: "Task A",
            project: "Work",
            priority: 2,
            sessionStartDate: start,
            focusIntervalStartDate: start,
            elapsedBeforePause: 0,
            isPaused: false
        )

        let nextTask = VTask(id: 2, title: "Task B", done: false, priority: 1, projectId: 99)
        manager.switchFocus(task: nextTask, projectName: "Home")

        // Persistence happens synchronously before the async startFocus Task fires.
        let records = try fetchRecords()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.taskId, 1, "Outgoing session — not the new one — should be persisted")
        XCTAssertEqual(record.focusedSeconds, 300, accuracy: 2)
        XCTAssertNil(manager.currentSession, "currentSession should be cleared synchronously")
    }

    // MARK: - handleTaskCompleted

    func testHandleTaskCompletedPersistsAndClearsMatchingSession() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date().addingTimeInterval(-180)
        manager.currentSession = makeSession(
            taskId: 7,
            sessionStartDate: start,
            focusIntervalStartDate: start,
            elapsedBeforePause: 0,
            isPaused: false
        )

        manager.handleTaskCompleted(taskId: 7)

        XCTAssertEqual(try fetchRecords().count, 1)
        XCTAssertNil(manager.currentSession)
    }

    func testHandleTaskCompletedIgnoresNonMatchingTask() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date().addingTimeInterval(-180)
        let session = makeSession(
            taskId: 7,
            sessionStartDate: start,
            focusIntervalStartDate: start,
            elapsedBeforePause: 0,
            isPaused: false
        )
        manager.currentSession = session

        manager.handleTaskCompleted(taskId: 999) // different task

        XCTAssertEqual(try fetchRecords().count, 0, "Unrelated completion must not persist or end the focus")
        XCTAssertNotNil(manager.currentSession)
        XCTAssertEqual(manager.currentSession?.taskId, 7)
    }

    // MARK: - Pause / resume accounting

    func testPauseResumeProducesActiveTimeOnly() throws {
        let manager = FocusManager(modelContainer: container)
        // Simulate: 5 minutes active, then paused (no current interval).
        // Wall-clock between pause and end can be arbitrary — the persisted
        // value should be the trusted elapsedBeforePause only.
        let start = Date().addingTimeInterval(-3600) // 1 hour ago
        manager.currentSession = makeSession(
            taskId: 5,
            sessionStartDate: start,
            focusIntervalStartDate: start.addingTimeInterval(300), // last interval started 55 min ago
            elapsedBeforePause: 300, // 5 min accumulated
            isPaused: true
        )

        manager.endFocus()

        let record = try XCTUnwrap(try fetchRecords().first)
        XCTAssertEqual(record.focusedSeconds, 300, accuracy: 1, "Paused session must not credit wall-clock time")
    }

    // MARK: - Stale-session restoration

    func testStaleSessionRestorePersistsElapsedBeforePauseOnly() throws {
        // Seed a session that's >24h old with a misleading focusIntervalStartDate
        // — if the implementation naively summed totalElapsed(at: Date()), it
        // would record 24h+ of "focus". Correct behaviour: only count
        // elapsedBeforePause (the trusted, observed accumulation).
        let twoDaysAgo = Date().addingTimeInterval(-48 * 3600)
        let staleSession = FocusSession(
            taskId: 11,
            taskTitle: "Long-running",
            projectName: "Work",
            priorityLevel: 1,
            sessionStartDate: twoDaysAgo,
            focusIntervalStartDate: twoDaysAgo.addingTimeInterval(1800), // active interval started 30 min in
            elapsedBeforePause: 1800, // 30 minutes accumulated, then app died
            isPaused: false
        )
        try seed(session: staleSession)

        // Constructing FocusManager triggers restoreSession, which detects stale and persists.
        _ = FocusManager(modelContainer: container)

        let record = try XCTUnwrap(try fetchRecords().first)
        XCTAssertEqual(record.taskId, 11)
        XCTAssertEqual(record.focusedSeconds, 1800, accuracy: 1)
        // endedAt should be sessionStartDate + elapsedBeforePause, not "now"
        let expectedEnd = twoDaysAgo.addingTimeInterval(1800)
        XCTAssertEqual(record.endedAt.timeIntervalSince1970, expectedEnd.timeIntervalSince1970, accuracy: 1)
    }

    func testFreshSessionIsRestoredNotPersisted() throws {
        // A session <24h old should be restored as live state, not persisted.
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let freshSession = FocusSession(
            taskId: 22,
            taskTitle: "Active",
            projectName: "Home",
            priorityLevel: 0,
            sessionStartDate: oneHourAgo,
            focusIntervalStartDate: oneHourAgo,
            elapsedBeforePause: 0,
            isPaused: false
        )
        try seed(session: freshSession)

        let manager = FocusManager(modelContainer: container)

        XCTAssertEqual(try fetchRecords().count, 0, "Fresh session must not be persisted on restore")
        XCTAssertEqual(manager.currentSession?.taskId, 22)
    }

    func testNoSessionInDefaultsIsNoOp() throws {
        // No seeded session at all.
        let manager = FocusManager(modelContainer: container)

        XCTAssertEqual(try fetchRecords().count, 0)
        XCTAssertNil(manager.currentSession)
    }

    // MARK: - Helpers

    private func makeSession(
        taskId: Int64 = 1,
        title: String = "Task",
        project: String = "Project",
        priority: Int = 0,
        sessionStartDate: Date,
        focusIntervalStartDate: Date,
        elapsedBeforePause: TimeInterval,
        isPaused: Bool
    ) -> FocusSession {
        FocusSession(
            taskId: taskId,
            taskTitle: title,
            projectName: project,
            priorityLevel: priority,
            sessionStartDate: sessionStartDate,
            focusIntervalStartDate: focusIntervalStartDate,
            elapsedBeforePause: elapsedBeforePause,
            isPaused: isPaused
        )
    }

    private func fetchRecords() throws -> [FocusRecord] {
        try container.mainContext.fetch(FetchDescriptor<FocusRecord>())
    }

    private func seed(session: FocusSession) throws {
        let data = try JSONEncoder().encode(session)
        FocusConstants.sharedDefaults.set(data, forKey: FocusConstants.focusSessionKey)
    }
}
#endif
