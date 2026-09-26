import XCTest
@testable import mDone

final class NotificationServiceTests: XCTestCase {
    func testReminderOffsetValues() {
        XCTAssertEqual(NotificationService.ReminderOffset.fifteenMinutes.timeInterval, 900)
        XCTAssertEqual(NotificationService.ReminderOffset.thirtyMinutes.timeInterval, 1800)
        XCTAssertEqual(NotificationService.ReminderOffset.oneHour.timeInterval, 3600)
        XCTAssertEqual(NotificationService.ReminderOffset.oneDay.timeInterval, 86400)
    }

    func testReminderOffsetLabels() {
        XCTAssertEqual(NotificationService.ReminderOffset.fifteenMinutes.label, "15 minutes before")
        XCTAssertEqual(NotificationService.ReminderOffset.thirtyMinutes.label, "30 minutes before")
        XCTAssertEqual(NotificationService.ReminderOffset.oneHour.label, "1 hour before")
        XCTAssertEqual(NotificationService.ReminderOffset.oneDay.label, "1 day before")
    }

    func testReminderOffsetAllCases() {
        XCTAssertEqual(NotificationService.ReminderOffset.allCases.count, 4)
    }

    // MARK: - plannedReminders

    private func task(
        id: Int64,
        dueInMinutes minutes: Double,
        reminders: [TaskReminder]? = nil,
        done: Bool = false,
        now: Date
    ) -> VTask {
        var t = VTask(id: id, title: "Task \(id)", done: done, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(minutes * 60)
        t.reminders = reminders
        return t
    }

    func testPlannedReminderFromDueDateUsesOffset() {
        let now = Date()
        // Due in 60 min, 30-min offset -> fires 30 min from now.
        let t = task(id: 1, dueInMinutes: 60, now: now)
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.identifier, "task-1")
        XCTAssertEqual(
            planned.first?.fireDate.timeIntervalSince1970 ?? 0,
            now.addingTimeInterval(30 * 60).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testPlannedRemindersSkipsPastAndDoneTasks() {
        let now = Date()
        // Reminder offset would put the fire time in the past.
        let past = task(id: 1, dueInMinutes: 10, now: now) // 10 - 30 = -20 min
        XCTAssertTrue(NotificationService.plannedReminders(for: past, offset: .thirtyMinutes, now: now).isEmpty)

        let doneTask = task(id: 2, dueInMinutes: 120, done: true, now: now)
        XCTAssertTrue(NotificationService.plannedReminders(for: doneTask, offset: .thirtyMinutes, now: now).isEmpty)
    }

    func testPlannedRemindersUsesPerTaskRemindersOverOffset() {
        let now = Date()
        let absolute = now.addingTimeInterval(45 * 60)
        var t = VTask(id: 7, title: "Multi", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(120 * 60)
        t.reminders = [
            TaskReminder(reminder: absolute, relativePeriod: nil, relativeTo: nil),
            // relativePeriod is seconds relative to due date (negative = before).
            TaskReminder(reminder: nil, relativePeriod: -3600, relativeTo: "due_date"),
        ]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(Set(planned.map(\.identifier)), ["task-7-0", "task-7-1"])
    }

    func testPlannedRemindersUsesAbsoluteWhenReferencedDateIsUnknown() {
        let now = Date()
        // The reminder is relative to a start date this task doesn't have
        // locally, so the server-computed absolute value is the only answer.
        let authoritative = now.addingTimeInterval(90 * 60)
        var t = VTask(id: 8, title: "Both", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(240 * 60)
        t.reminders = [
            TaskReminder(reminder: authoritative, relativePeriod: -3600, relativeTo: "start_date"),
        ]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(
            planned.first?.fireDate.timeIntervalSince1970 ?? 0,
            authoritative.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testRelativeReminderFollowsLocallyMovedDueDate() {
        let now = Date()
        // An offline postpone moves the due date but leaves the server's old
        // absolute value in place until the edit syncs. The reminder has to
        // follow the new due date, not fire at the stale time.
        let staleAbsolute = now.addingTimeInterval(30 * 60)
        var t = VTask(id: 10, title: "Postponed", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(25 * 3600)
        t.reminders = [
            TaskReminder(reminder: staleAbsolute, relativePeriod: -1800, relativeTo: "due_date"),
        ]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(
            planned.first?.fireDate.timeIntervalSince1970 ?? 0,
            now.addingTimeInterval(25 * 3600 - 1800).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testRelativeReminderUsesTheDateItPointsAt() {
        let now = Date()
        var t = VTask(id: 11, title: "Ranges", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(10 * 3600)
        t.startDate = now.addingTimeInterval(2 * 3600)
        t.endDate = now.addingTimeInterval(6 * 3600)
        t.reminders = [
            TaskReminder(reminder: nil, relativePeriod: -600, relativeTo: "start_date"),
            TaskReminder(reminder: nil, relativePeriod: -600, relativeTo: "end_date"),
        ]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.map(\.identifier), ["task-11-0", "task-11-1"])
        XCTAssertEqual(
            planned[0].fireDate.timeIntervalSince1970,
            now.addingTimeInterval(2 * 3600 - 600).timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(
            planned[1].fireDate.timeIntervalSince1970,
            now.addingTimeInterval(6 * 3600 - 600).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testAbsoluteOnlyReminderIsUsedAsIs() {
        let now = Date()
        let at = now.addingTimeInterval(3 * 3600)
        var t = VTask(id: 12, title: "Absolute", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(10 * 3600)
        t.reminders = [TaskReminder(reminder: at, relativePeriod: nil, relativeTo: nil)]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.first?.fireDate.timeIntervalSince1970 ?? 0, at.timeIntervalSince1970, accuracy: 1)
    }

    func testPlannedRemindersFallBackToRelativePeriodWhenNoAbsolute() {
        let now = Date()
        // No absolute value -> fall back to due_date + relative_period.
        var t = VTask(id: 9, title: "Rel", done: false, priority: 0, projectId: 1)
        t.dueDate = now.addingTimeInterval(120 * 60)
        t.reminders = [
            TaskReminder(reminder: nil, relativePeriod: -3600, relativeTo: "due_date"),
        ]
        let planned = NotificationService.plannedReminders(for: t, offset: .thirtyMinutes, now: now)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(
            planned.first?.fireDate.timeIntervalSince1970 ?? 0,
            now.addingTimeInterval(60 * 60).timeIntervalSince1970, // 120 - 60 min
            accuracy: 1
        )
    }

    // MARK: - prioritized (cap under the iOS 64-notification ceiling)

    func testPrioritizedCapsToLimitAndKeepsSoonest() {
        let base = Date()
        // 100 reminders, each 1 minute further out than the last.
        let reminders = (0 ..< 100).map { i in
            NotificationService.PlannedReminder(
                identifier: "task-\(i)",
                taskId: Int64(i),
                title: "T\(i)",
                fireDate: base.addingTimeInterval(Double(i) * 60)
            )
        }
        let result = NotificationService.prioritized(reminders, limit: 60)
        XCTAssertEqual(result.count, 60, "must not exceed the cap")
        // The soonest 60 (indices 0...59) must be the ones kept.
        XCTAssertEqual(result.map(\.taskId), Array(0 ..< 60).map(Int64.init))
    }

    func testPrioritizedSortsByFireDateAscending() {
        let base = Date()
        let unsorted = [
            NotificationService.PlannedReminder(
                identifier: "c",
                taskId: 3,
                title: "c",
                fireDate: base.addingTimeInterval(300)
            ),
            NotificationService.PlannedReminder(
                identifier: "a",
                taskId: 1,
                title: "a",
                fireDate: base.addingTimeInterval(100)
            ),
            NotificationService.PlannedReminder(
                identifier: "b",
                taskId: 2,
                title: "b",
                fireDate: base.addingTimeInterval(200)
            ),
        ]
        let result = NotificationService.prioritized(unsorted, limit: 60)
        XCTAssertEqual(result.map(\.taskId), [1, 2, 3])
    }

    func testPrioritizedBreaksTiesByIdentifier() {
        let fire = Date().addingTimeInterval(500)
        let tied = [
            NotificationService.PlannedReminder(identifier: "task-9", taskId: 9, title: "9", fireDate: fire),
            NotificationService.PlannedReminder(identifier: "task-1", taskId: 1, title: "1", fireDate: fire),
        ]
        let result = NotificationService.prioritized(tied, limit: 60)
        XCTAssertEqual(result.map(\.identifier), ["task-1", "task-9"])
    }

    func testDefaultLimitMatchesMaxPendingReminders() {
        let base = Date()
        let reminders = (0 ..< 80).map { i in
            NotificationService.PlannedReminder(
                identifier: "task-\(i)",
                taskId: Int64(i),
                title: "T\(i)",
                fireDate: base.addingTimeInterval(Double(i))
            )
        }
        // Using the default limit must clamp to maxPendingReminders and stay
        // safely under iOS's hard ceiling of 64.
        let result = NotificationService.prioritized(reminders)
        XCTAssertEqual(result.count, NotificationService.maxPendingReminders)
        XCTAssertLessThan(result.count, 64)
    }

    // MARK: - staleIdentifiers (reconcile instead of remove-all)

    func testStaleIdentifiersRemovesOnlyUnwantedTaskReminders() {
        let wanted = [
            NotificationService.PlannedReminder(identifier: "task-1", taskId: 1, title: "1", fireDate: Date()),
            NotificationService.PlannedReminder(identifier: "task-2-0", taskId: 2, title: "2", fireDate: Date()),
        ]
        let stale = NotificationService.staleIdentifiers(
            pending: ["task-1", "task-2-0", "task-3", "task-2-1", "focus-end"],
            wanted: wanted
        )
        XCTAssertEqual(stale, ["task-3", "task-2-1"], "keeps wanted ones and anything that isn't a task reminder")
    }
}
