import XCTest
@testable import mDone

/// The advanced filter sheet's matching rules, and how `AppState` layers it
/// with the filter chips and search. The filter used to fetch a single server
/// page into `AppState.tasks`, which dropped tasks past the 50th, hid done
/// results behind the Inbox's open-only sections, and was undone by any
/// refresh; these tests pin the local replacement.
final class AdvancedTaskFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 30 September 2026, 14:30 UTC.
    private var now: Date {
        date(2026, 9, 30, 14, 30)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func task(
        _ id: Int64,
        done: Bool = false,
        due: Date? = nil,
        priority: Int64 = 0,
        projectId: Int64 = 1
    ) -> VTask {
        VTask(id: id, title: "Task \(id)", done: done, dueDate: due, priority: priority, projectId: projectId)
    }

    private func ids(_ filter: AdvancedTaskFilter, _ tasks: [VTask]) -> [Int64] {
        filter.apply(to: tasks, now: now, calendar: calendar).map(\.id)
    }

    // MARK: - Active state

    func testDefaultsAreInactiveAndReturnEverything() {
        let filter = AdvancedTaskFilter()
        XCTAssertFalse(filter.isActive)
        let tasks = [task(1), task(2, done: true)]
        XCTAssertEqual(ids(filter, tasks), [1, 2])
    }

    func testCustomDatesAloneDoNotActivate() {
        var filter = AdvancedTaskFilter()
        filter.customStart = date(2020, 1, 1)
        filter.customEnd = date(2030, 1, 1)
        XCTAssertFalse(filter.isActive, "custom dates only count when the Custom Range is chosen")
    }

    func testEachCriterionActivates() {
        var priority = AdvancedTaskFilter()
        priority.priority = .high
        var range = AdvancedTaskFilter()
        range.dateRange = .today
        var status = AdvancedTaskFilter()
        status.status = .any
        var project = AdvancedTaskFilter()
        project.projectId = 7
        for filter in [priority, range, status, project] {
            XCTAssertTrue(filter.isActive)
        }
    }

    // MARK: - Status, priority, project

    func testStatusDoneReturnsOnlyDoneTasks() {
        var filter = AdvancedTaskFilter()
        filter.status = .done
        XCTAssertEqual(ids(filter, [task(1), task(2, done: true), task(3, done: true)]), [2, 3])
    }

    func testStatusAnyReturnsBoth() {
        var filter = AdvancedTaskFilter()
        filter.status = .any
        XCTAssertEqual(ids(filter, [task(1), task(2, done: true)]), [1, 2])
    }

    func testPriorityMatchesExactLevelAndKeepsUndoneDefault() {
        var filter = AdvancedTaskFilter()
        filter.priority = .high
        let tasks = [task(1, priority: 3), task(2, priority: 4), task(3, done: true, priority: 3), task(4)]
        XCTAssertEqual(ids(filter, tasks), [1])
    }

    func testPriorityNoneMatchesTasksWithoutPriority() {
        var filter = AdvancedTaskFilter()
        filter.priority = PriorityLevel.none
        XCTAssertEqual(ids(filter, [task(1), task(2, priority: 2)]), [1])
    }

    func testProjectFilter() {
        var filter = AdvancedTaskFilter()
        filter.projectId = 5
        XCTAssertEqual(ids(filter, [task(1, projectId: 5), task(2, projectId: 6)]), [1])
    }

    func testCriteriaCombineWithAnd() {
        var filter = AdvancedTaskFilter()
        filter.priority = .urgent
        filter.projectId = 5
        filter.dateRange = .today
        let tasks = [
            task(1, due: date(2026, 9, 30, 18), priority: 4, projectId: 5),
            task(2, due: date(2026, 9, 30, 18), priority: 4, projectId: 6),
            task(3, due: date(2026, 10, 1, 18), priority: 4, projectId: 5),
            task(4, due: date(2026, 9, 30, 18), priority: 3, projectId: 5),
        ]
        XCTAssertEqual(ids(filter, tasks), [1])
    }

    // MARK: - Date ranges

    func testDateRangeExcludesTasksWithoutDueDate() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .thisMonth
        // Vikunja's zero date decodes to year 1 and means "no due date".
        let zeroDate = date(1, 1, 1)
        XCTAssertEqual(ids(filter, [task(1), task(2, due: zeroDate), task(3, due: date(2026, 9, 30, 20))]), [3])
    }

    func testOverdue() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .overdue
        let tasks = [
            task(1, due: date(2026, 9, 30, 9)), // earlier today, timed
            task(2, due: date(2026, 9, 30)), // today, date-only: not overdue until tonight
            task(3, due: date(2026, 9, 29)), // yesterday, date-only
            task(4, due: date(2026, 9, 30, 18)), // later today
        ]
        XCTAssertEqual(ids(filter, tasks), [1, 3])
    }

    func testToday() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .today
        let tasks = [
            task(1, due: date(2026, 9, 30)),
            task(2, due: date(2026, 9, 30, 23, 59)),
            task(3, due: date(2026, 10, 1)),
            task(4, due: date(2026, 9, 29, 23, 59)),
        ]
        XCTAssertEqual(ids(filter, tasks), [1, 2])
    }

    func testThisWeekIsTodayPlusSixDays() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .thisWeek
        let tasks = [
            task(1, due: date(2026, 9, 30, 8)),
            task(2, due: date(2026, 10, 6, 23)),
            task(3, due: date(2026, 10, 7)),
            task(4, due: date(2026, 9, 29, 23)),
        ]
        XCTAssertEqual(ids(filter, tasks), [1, 2])
    }

    func testThisMonthRunsFromTodayToMonthEnd() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .thisMonth
        let tasks = [
            task(1, due: date(2026, 9, 30, 23)),
            task(2, due: date(2026, 10, 1)),
            task(3, due: date(2026, 9, 15)),
        ]
        XCTAssertEqual(ids(filter, tasks), [1])
    }

    func testCustomRangeIncludesWholeEndDay() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .custom
        filter.customStart = date(2026, 10, 5, 16)
        filter.customEnd = date(2026, 10, 10, 9)
        let tasks = [
            task(1, due: date(2026, 10, 5, 8)),
            task(2, due: date(2026, 10, 10, 22)),
            task(3, due: date(2026, 10, 11)),
            task(4, due: date(2026, 10, 4, 23)),
        ]
        XCTAssertEqual(ids(filter, tasks), [1, 2])
    }

    func testCustomRangePickedBackwardsStillWorks() {
        var filter = AdvancedTaskFilter()
        filter.dateRange = .custom
        filter.customStart = date(2026, 10, 10)
        filter.customEnd = date(2026, 10, 5)
        XCTAssertEqual(ids(filter, [task(1, due: date(2026, 10, 7))]), [1])
    }

    // MARK: - Filter chips

    func testChipFilters() {
        let labelled = VTask(
            id: 4,
            title: "L",
            done: false,
            priority: 0,
            projectId: 1,
            labels: [VLabel(id: 1, title: "x")]
        )
        let tasks = [task(1, priority: 3), task(2, priority: 5), task(3, done: true, priority: 1), labelled]
        XCTAssertEqual(TaskFilter.all.apply(to: tasks).map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(TaskFilter.highPriority.apply(to: tasks).map(\.id), [1, 2])
        XCTAssertEqual(TaskFilter.completed.apply(to: tasks).map(\.id), [3])
        XCTAssertEqual(TaskFilter.hasLabels.apply(to: tasks).map(\.id), [4])
    }
}

// MARK: - AppState integration

@MainActor
final class AppStateFilteringTests: XCTestCase {
    private func task(_ id: Int64, title: String? = nil, done: Bool = false, priority: Int64 = 0) -> VTask {
        VTask(id: id, title: title ?? "Task \(id)", done: done, priority: priority, projectId: 1)
    }

    func testNothingActiveMeansNotFiltering() {
        let appState = AppState()
        appState.tasks = [task(1), task(2, done: true)]
        XCTAssertFalse(appState.isFiltering)
        XCTAssertEqual(appState.filteredTasks.map(\.id), [1, 2])
    }

    func testApplyingDefaultsDoesNotCountAsFiltering() {
        let appState = AppState()
        appState.advancedFilter = AdvancedTaskFilter()
        XCTAssertFalse(appState.isFiltering)
    }

    func testDoneFilterFindsDoneTasksWithoutTouchingTheList() {
        let appState = AppState()
        appState.tasks = [task(1), task(2, done: true)]
        var filter = AdvancedTaskFilter()
        filter.status = .done
        appState.advancedFilter = filter

        XCTAssertTrue(appState.isFiltering)
        XCTAssertEqual(appState.filteredTasks.map(\.id), [2])
        XCTAssertEqual(appState.tasks.map(\.id), [1, 2], "filtering must never replace the task list")
    }

    func testFilterSurvivesTheTaskListBeingRefreshed() {
        let appState = AppState()
        appState.tasks = [task(1, priority: 3), task(2)]
        var filter = AdvancedTaskFilter()
        filter.priority = .high
        appState.advancedFilter = filter

        // What refreshAll() does: replace the whole list.
        appState.tasks = [task(1, priority: 3), task(2), task(3, priority: 3)]

        XCTAssertTrue(appState.advancedFilter.isActive)
        XCTAssertEqual(appState.filteredTasks.map(\.id), [1, 3])
    }

    func testResetRestoresEveryTask() {
        let appState = AppState()
        appState.tasks = (1 ... 60).map { task(Int64($0), priority: $0 == 1 ? 3 : 0) }
        var filter = AdvancedTaskFilter()
        filter.priority = .high
        appState.advancedFilter = filter
        XCTAssertEqual(appState.filteredTasks.count, 1)

        appState.advancedFilter = AdvancedTaskFilter()

        XCTAssertFalse(appState.isFiltering)
        XCTAssertEqual(appState.filteredTasks.count, 60, "no page-size truncation after Reset")
    }

    func testAdvancedFilterChipAndSearchCombine() {
        let appState = AppState()
        appState.tasks = [
            task(1, title: "Pay rent", priority: 3),
            task(2, title: "Pay tax", priority: 1),
            task(3, title: "Walk dog", priority: 4),
            task(4, title: "Pay bills", done: true, priority: 4),
        ]
        var filter = AdvancedTaskFilter()
        filter.status = .undone
        filter.projectId = 1
        appState.advancedFilter = filter
        appState.activeFilter = .highPriority
        appState.searchQuery = "pay"

        XCTAssertEqual(appState.filteredTasks.map(\.id), [1])
    }

    func testClearingSearchBringsTheFullListBack() {
        let appState = AppState()
        appState.tasks = [task(1, title: "Book dentist"), task(2, title: "Renew passport")]
        appState.searchQuery = "book"
        XCTAssertEqual(appState.filteredTasks.map(\.id), [1])

        appState.searchQuery = ""

        XCTAssertFalse(appState.isFiltering)
        XCTAssertEqual(appState.tasks.map(\.id), [1, 2])
    }

    func testSearchMatchesDescriptionAndIgnoresCaseAndAccents() {
        var described = task(1, title: "Errand")
        described.description = "<p>Pick up the CAFÉ order</p>"
        let appState = AppState()
        appState.tasks = [described, task(2, title: "Other")]

        appState.searchQuery = "cafe"
        XCTAssertEqual(appState.filteredTasks.map(\.id), [1])

        appState.searchQuery = "  errand  "
        XCTAssertEqual(appState.filteredTasks.map(\.id), [1], "surrounding whitespace is ignored")
    }
}
