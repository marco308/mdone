import XCTest
@testable import mDone

/// `AppState.tasksForReminders` decides which tasks reminders are rebuilt
/// from. While `tasks` holds search or filter results, rebuilding from it
/// alone would wipe every other task's reminder.
final class ReminderSourceTests: XCTestCase {
    private func task(_ id: Int64, title: String = "T") -> VTask {
        VTask(id: id, title: title, done: false, priority: 0, projectId: 1)
    }

    func testFullListIsUsedAsIs() {
        let visible = [task(1), task(2)]
        let result = AppState.tasksForReminders(visible: visible, visibleIsPartial: false, cached: [task(3)])
        XCTAssertEqual(result?.map(\.id), [1, 2])
    }

    func testPartialListIsMergedOverTheCache() {
        let visible = [task(2, title: "fresh")]
        let cached = [task(1), task(2, title: "stale"), task(3)]
        let result = AppState.tasksForReminders(visible: visible, visibleIsPartial: true, cached: cached)
        XCTAssertEqual(result.map { Set($0.map(\.id)) }, [1, 2, 3])
        XCTAssertEqual(result?.first { $0.id == 2 }?.title, "fresh", "the in-memory copy wins")
    }

    func testPartialListWithoutCacheLeavesRemindersAlone() {
        XCTAssertNil(AppState.tasksForReminders(visible: [task(1)], visibleIsPartial: true, cached: nil))
        XCTAssertNil(AppState.tasksForReminders(visible: [task(1)], visibleIsPartial: true, cached: []))
    }
}
