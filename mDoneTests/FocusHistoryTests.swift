#if os(iOS)
import SwiftData
import XCTest
@testable import mDone

@MainActor
final class FocusHistoryTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([FocusRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - persistCompletedSession

    func testPersistInsertsRecordWithSessionFields() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(taskId: 42, title: "Write report", project: "Work", priority: 3, start: start)

        manager.persistCompletedSession(session, endedAt: start.addingTimeInterval(600), focusedSeconds: 600)

        let records = try container.mainContext.fetch(FetchDescriptor<FocusRecord>())
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.taskId, 42)
        XCTAssertEqual(record.taskTitle, "Write report")
        XCTAssertEqual(record.projectName, "Work")
        XCTAssertEqual(record.priorityLevel, 3)
        XCTAssertEqual(record.startedAt, start)
        XCTAssertEqual(record.endedAt, start.addingTimeInterval(600))
        XCTAssertEqual(record.focusedSeconds, 600)
        XCTAssertFalse(record.device.isEmpty)
    }

    func testPersistDropsZeroDurationSession() throws {
        let manager = FocusManager(modelContainer: container)
        let session = makeSession(taskId: 1, start: Date())

        manager.persistCompletedSession(session, endedAt: Date(), focusedSeconds: 0)
        manager.persistCompletedSession(session, endedAt: Date(), focusedSeconds: 0.4)

        let records = try container.mainContext.fetch(FetchDescriptor<FocusRecord>())
        XCTAssertTrue(records.isEmpty, "Sub-second sessions should be dropped")
    }

    func testPersistWithoutContainerIsNoOp() throws {
        // FocusManager built with no container (e.g. a unit test path that never wired
        // SwiftData) should silently no-op rather than crash.
        let manager = FocusManager(modelContainer: nil)
        let session = makeSession(taskId: 1, start: Date())
        manager.persistCompletedSession(session, endedAt: Date(), focusedSeconds: 60)
        // No assertion needed — the test passes if this didn't crash.
    }

    func testMultipleSessionsAccumulateAsSeparateRecords() throws {
        let manager = FocusManager(modelContainer: container)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(taskId: 7, start: start)

        manager.persistCompletedSession(session, endedAt: start.addingTimeInterval(300), focusedSeconds: 300)
        manager.persistCompletedSession(session, endedAt: start.addingTimeInterval(900), focusedSeconds: 600)
        manager.persistCompletedSession(session, endedAt: start.addingTimeInterval(1200), focusedSeconds: 200)

        let records = try container.mainContext.fetch(FetchDescriptor<FocusRecord>())
        XCTAssertEqual(records.count, 3, "Each sitting should be its own record, not merged")
    }

    // MARK: - FocusHistoryQuery

    func testTotalFocusSumsAllRecordsForTask() {
        seed(taskId: 100, seconds: [600, 900, 300])
        seed(taskId: 999, seconds: [100]) // different task — must not contribute

        let total = FocusHistoryQuery.totalFocus(for: 100, in: container.mainContext)
        XCTAssertEqual(total, 1800)
    }

    func testTotalFocusReturnsZeroForUnknownTask() {
        seed(taskId: 100, seconds: [600])
        XCTAssertEqual(FocusHistoryQuery.totalFocus(for: 999, in: container.mainContext), 0)
    }

    func testSessionCountForTask() {
        seed(taskId: 5, seconds: [60, 120, 180])
        seed(taskId: 6, seconds: [60])

        XCTAssertEqual(FocusHistoryQuery.sessionCount(for: 5, in: container.mainContext), 3)
        XCTAssertEqual(FocusHistoryQuery.sessionCount(for: 6, in: container.mainContext), 1)
        XCTAssertEqual(FocusHistoryQuery.sessionCount(for: 99, in: container.mainContext), 0)
    }

    // MARK: - Helpers

    private func makeSession(
        taskId: Int64 = 1,
        title: String = "Task",
        project: String = "Project",
        priority: Int = 0,
        start: Date
    ) -> FocusSession {
        FocusSession(
            taskId: taskId,
            taskTitle: title,
            projectName: project,
            priorityLevel: priority,
            sessionStartDate: start,
            focusIntervalStartDate: start,
            elapsedBeforePause: 0,
            isPaused: false
        )
    }

    private func seed(taskId: Int64, seconds: [TimeInterval]) {
        let context = container.mainContext
        for s in seconds {
            let record = FocusRecord(
                taskId: taskId,
                taskTitle: "t",
                projectName: "p",
                priorityLevel: 0,
                startedAt: Date(),
                endedAt: Date(),
                focusedSeconds: s,
                device: "test"
            )
            context.insert(record)
        }
        try? context.save()
    }
}
#endif
