import XCTest
@testable import mDone

/// The sort menu's model: which orders each list offers, what a tap does,
/// how the choice is stored, and that Manual leaves the server's order alone.
final class TaskSortOrderTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TaskSortOrderTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func task(_ id: Int64, title: String = "", due: Date? = nil, priority: Int64 = 0) -> VTask {
        var task = VTask(id: id, title: title, done: false, priority: priority, projectId: 1)
        task.dueDate = due
        return task
    }

    // MARK: - Ordering

    func testManualKeepsTheGivenOrder() {
        let tasks = [task(3, title: "c"), task(1, title: "a"), task(2, title: "b")]
        XCTAssertEqual(TaskSortOrder.manual.apply(to: tasks).map(\.id), [3, 1, 2])
        XCTAssertEqual(TaskSortOrder.manual.apply(to: tasks, ascending: false).map(\.id), [3, 1, 2])
    }

    func testDueDateSortsSoonestFirstAndUndatedLast() {
        let now = Date()
        let tasks = [
            task(1, due: now.addingTimeInterval(7200)),
            task(2),
            task(3, due: now),
        ]
        XCTAssertEqual(TaskSortOrder.dueDate.apply(to: tasks).map(\.id), [3, 1, 2])
        XCTAssertEqual(TaskSortOrder.dueDate.apply(to: tasks, ascending: false).map(\.id), [2, 1, 3])
    }

    func testPrioritySortsHighestFirst() {
        let tasks = [task(1, priority: 1), task(2, priority: 5), task(3, priority: 3)]
        XCTAssertEqual(TaskSortOrder.priority.apply(to: tasks).map(\.id), [2, 3, 1])
    }

    func testTitleSortsAlphabetically() {
        let tasks = [task(1, title: "banana"), task(2, title: "Apple"), task(3, title: "cherry")]
        XCTAssertEqual(TaskSortOrder.title.apply(to: tasks).map(\.id), [2, 1, 3])
    }

    func testOnlyManualHasNoDirection() {
        XCTAssertFalse(TaskSortOrder.manual.supportsDirection)
        XCTAssertTrue(TaskSortOrder.dueDate.supportsDirection)
        XCTAssertTrue(TaskSortOrder.priority.supportsDirection)
        XCTAssertTrue(TaskSortOrder.title.supportsDirection)
    }

    // MARK: - Scope

    func testInboxDoesNotOfferManual() {
        XCTAssertFalse(TaskSortScope.inbox.allowsManual)
        XCTAssertEqual(TaskSortScope.inbox.availableOrders, [.dueDate, .priority, .title])
    }

    func testProjectOffersManual() {
        XCTAssertTrue(TaskSortScope.project(7).allowsManual)
        XCTAssertEqual(TaskSortScope.project(7).availableOrders, [.manual, .dueDate, .priority, .title])
    }

    func testEachProjectHasItsOwnStorageKey() {
        XCTAssertNotEqual(TaskSortScope.project(1).storageKey, TaskSortScope.project(2).storageKey)
        XCTAssertNotEqual(TaskSortScope.project(1).storageKey, TaskSortScope.inbox.storageKey)
    }

    // MARK: - Selecting in the menu

    func testSelectingAnotherOrderStartsAscending() {
        let preference = TaskSortPreference(order: .dueDate, ascending: false)
        XCTAssertEqual(preference.selecting(.title), TaskSortPreference(order: .title, ascending: true))
    }

    func testSelectingTheCurrentOrderFlipsDirection() {
        let preference = TaskSortPreference(order: .dueDate, ascending: true)
        XCTAssertEqual(preference.selecting(.dueDate), TaskSortPreference(order: .dueDate, ascending: false))
    }

    func testSelectingManualTwiceStaysManual() {
        let preference = TaskSortPreference(order: .manual, ascending: true)
        XCTAssertEqual(preference.selecting(.manual), preference)
    }

    // MARK: - Persistence

    func testDefaultIsDueDateAscending() {
        XCTAssertEqual(TaskSortPreference.default, TaskSortPreference(order: .dueDate, ascending: true))
        XCTAssertEqual(TaskSortPreference.load(for: .project(7), defaults: defaults), .default)
    }

    func testSaveThenLoadRoundTrips() {
        let preference = TaskSortPreference(order: .title, ascending: false)
        preference.save(for: .project(7), defaults: defaults)

        XCTAssertEqual(TaskSortPreference.load(for: .project(7), defaults: defaults), preference)
        XCTAssertEqual(TaskSortPreference.load(for: .project(8), defaults: defaults), .default, "other project")
    }

    func testManualRoundTrips() {
        TaskSortPreference(order: .manual, ascending: true).save(for: .project(7), defaults: defaults)
        XCTAssertEqual(TaskSortPreference.load(for: .project(7), defaults: defaults).order, .manual)
    }

    /// A stored Manual choice on a list that cannot show it (the Inbox) falls
    /// back rather than leaving the list unsorted.
    func testManualStoredForInboxFallsBackToDefault() {
        TaskSortPreference(order: .manual, ascending: true).save(for: .inbox, defaults: defaults)
        XCTAssertEqual(TaskSortPreference.load(for: .inbox, defaults: defaults), .default)
    }

    func testGarbageInDefaultsFallsBackToDefault() {
        defaults.set("what", forKey: TaskSortScope.project(7).storageKey)
        XCTAssertEqual(TaskSortPreference.load(for: .project(7), defaults: defaults), .default)
        XCTAssertNil(TaskSortPreference(storedValue: ""))
        XCTAssertNil(TaskSortPreference(storedValue: "sideways:asc"))
        XCTAssertNil(TaskSortPreference(storedValue: "dueDate:sideways"), "only asc and desc are directions")
    }

    /// A comparator that negates its result for descending is not a strict
    /// weak ordering: equal elements would sort "before" each other both
    /// ways. Ties must compare false in both directions.
    func testDescendingComparatorKeepsTiesStable() {
        let tied = (1 ... 6).map { task(Int64($0), priority: 3) }
        XCTAssertEqual(TaskSortOrder.priority.apply(to: tied, ascending: false).map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(TaskSortOrder.priority.apply(to: tied, ascending: true).map(\.id), [1, 2, 3, 4, 5, 6])

        let mixed = [task(1, priority: 1), task(2, priority: 5), task(3, priority: 1), task(4, priority: 5)]
        XCTAssertEqual(TaskSortOrder.priority.apply(to: mixed, ascending: false).map(\.id), [1, 3, 2, 4])
    }

    func testStoredValueFormat() {
        XCTAssertEqual(TaskSortPreference(order: .priority, ascending: false).storedValue, "priority:desc")
        XCTAssertEqual(
            TaskSortPreference(storedValue: "priority:desc"),
            TaskSortPreference(order: .priority, ascending: false)
        )
        XCTAssertEqual(TaskSortPreference(storedValue: "manual"), TaskSortPreference(order: .manual, ascending: true))
    }
}
