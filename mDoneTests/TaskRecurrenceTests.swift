import XCTest
@testable import mDone

/// Issue #35: Vikunja stores one instance of a repeating task and advances its
/// due date only when the task is completed, so every future occurrence the app
/// shows on a later date is worked out here. These tests pin that arithmetic
/// against Vikunja's documented behaviour for each repeat mode.
///
/// The calendar and time zone are fixed, because two of the rules below only
/// differ from the obvious implementation on a day that is not 24 hours long.
final class TaskRecurrenceTests: XCTestCase {
    private let calendar: Calendar = {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
        return gregorian
    }()

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 9,
        _ minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func monthWindow(_ year: Int, _ month: Int) throws -> Range<Date> {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
        let end = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: start))
        return start ..< end
    }

    // MARK: - Reading the two API fields

    func testNoRepeatFieldsMeansNoRecurrence() {
        XCTAssertNil(TaskRecurrence(repeatAfter: nil, repeatMode: nil))
    }

    func testZeroIntervalWithoutAModeMeansNoRecurrence() {
        XCTAssertNil(TaskRecurrence(repeatAfter: 0, repeatMode: nil))
    }

    func testIntervalIsReadWithoutAMode() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 86400, repeatMode: nil), .interval(seconds: 86400))
    }

    func testIntervalIsReadWithModeZero() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 86400, repeatMode: 0), .interval(seconds: 86400))
    }

    /// The defect that made every other fix in this issue impossible for
    /// monthly tasks. Vikunja's monthly mode carries `repeat_after = 0`, so
    /// reading the interval alone made a monthly task look like it did not
    /// repeat: no badge, no description, and nothing to project from.
    func testMonthlyModeWithAZeroIntervalStillRepeats() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 0, repeatMode: 1), .monthly)
    }

    func testMonthlyModeIgnoresWhateverIntervalItCarries() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 2_592_000, repeatMode: 1), .monthly)
    }

    func testFromCompletionModeIsRead() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 86400, repeatMode: 2), .fromCompletion(seconds: 86400))
    }

    func testFromCompletionModeNeedsAnInterval() {
        XCTAssertNil(TaskRecurrence(repeatAfter: 0, repeatMode: 2))
    }

    /// A mode a future server adds is read as an interval rather than dropped,
    /// so the task keeps its badge and its projection instead of silently
    /// becoming non-repeating on an upgrade.
    func testAnUnknownModeIsReadAsAnInterval() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 86400, repeatMode: 99), .interval(seconds: 86400))
    }

    func testOnlyFromCompletionIsUnprojectable() {
        XCTAssertTrue(TaskRecurrence.interval(seconds: 86400).isProjectable)
        XCTAssertTrue(TaskRecurrence.monthly.isProjectable)
        XCTAssertFalse(TaskRecurrence.fromCompletion(seconds: 86400).isProjectable)
    }

    func testMonthlyModeReadsAsMonthly() {
        XCTAssertEqual(TaskRecurrence(repeatAfter: 0, repeatMode: 1)?.label, "Monthly")
    }

    // MARK: - Interval mode (repeat_mode 0)

    func testNextOccurrenceIsNeverTheDueDateItself() throws {
        // The due date is a real placement, not a projection.
        let due = try date(2026, 5, 10)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: due, calendar: calendar),
            try date(2026, 5, 11)
        )
    }

    func testNextOccurrenceFromBeforeTheDueDateIsTheFirstRepeat() throws {
        let due = try date(2026, 5, 10)
        let earlier = try date(2026, 5, 1)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: earlier, calendar: calendar),
            try date(2026, 5, 11)
        )
    }

    func testLandingExactlyOnAnOccurrenceReturnsTheFollowingOne() throws {
        let due = try date(2026, 5, 10)
        let onTheDot = try date(2026, 5, 12)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: onTheDot, calendar: calendar),
            try date(2026, 5, 13)
        )
    }

    /// `repeat_mode = 0` adds the interval repeatedly until the due date is in
    /// the future, so a daily task three days overdue comes back today, not
    /// three days ago and not tomorrow.
    func testAnOverdueIntervalSkipsForwardToToday() throws {
        let due = try date(2026, 5, 10)
        let now = try date(2026, 5, 13, 7)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: now, calendar: calendar),
            try date(2026, 5, 13)
        )
    }

    func testAnOverduePastTodaysTimeSkipsToTomorrow() throws {
        let due = try date(2026, 5, 10)
        let now = try date(2026, 5, 13, 10)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: now, calendar: calendar),
            try date(2026, 5, 14)
        )
    }

    /// The deliberate divergence from calendar arithmetic, and the reason this
    /// suite fixes a time zone. Vikunja adds a fixed number of seconds, so a
    /// daily task crossing the end of summer time lands an hour earlier by the
    /// wall clock. Adding one calendar day would keep 09:00 and put the app an
    /// hour out from the server twice a year.
    func testIntervalStepsBySecondsAcrossADaylightSavingChange() throws {
        let due = try date(2026, 10, 24)
        XCTAssertEqual(
            TaskRecurrence.interval(seconds: 86400).nextOccurrence(dueDate: due, after: due, calendar: calendar),
            try date(2026, 10, 25, 8)
        )
    }

    // MARK: - Monthly mode (repeat_mode 1)

    func testMonthlyClampsIntoAShorterMonth() throws {
        let due = try date(2027, 1, 31)
        XCTAssertEqual(
            TaskRecurrence.monthly.nextOccurrence(dueDate: due, after: due, calendar: calendar),
            try date(2027, 2, 28)
        )
    }

    /// Counting months from the original due date, rather than iterating "add
    /// one month" to the last result, is what lets the 31st come back. Iterating
    /// would settle on the 28th permanently after the first short month.
    func testMonthlyReturnsToTheOriginalDayOfMonth() throws {
        let due = try date(2027, 1, 31)
        let afterFebruary = try date(2027, 2, 28, 12)
        XCTAssertEqual(
            TaskRecurrence.monthly.nextOccurrence(dueDate: due, after: afterFebruary, calendar: calendar),
            try date(2027, 3, 31)
        )
    }

    func testMonthlyLandsOnTheLeapDay() throws {
        let due = try date(2028, 1, 31)
        XCTAssertEqual(
            TaskRecurrence.monthly.nextOccurrence(dueDate: due, after: due, calendar: calendar),
            try date(2028, 2, 29)
        )
    }

    func testAnOverdueMonthlySkipsForwardToTheNextMonthEnd() throws {
        let due = try date(2026, 1, 15)
        let now = try date(2026, 4, 20)
        XCTAssertEqual(
            TaskRecurrence.monthly.nextOccurrence(dueDate: due, after: now, calendar: calendar),
            try date(2026, 5, 15)
        )
    }

    // MARK: - From-completion mode (repeat_mode 2)

    /// Its next due date is the completion time plus the interval, so it cannot
    /// be known before the user actually completes the task. The app declines to
    /// guess rather than showing a date it would then have to correct.
    func testFromCompletionProjectsNothingAtAll() throws {
        let due = try date(2026, 5, 10)
        let recurrence = TaskRecurrence.fromCompletion(seconds: 86400)

        XCTAssertNil(recurrence.nextOccurrence(dueDate: due, after: due, calendar: calendar))
        XCTAssertTrue(
            recurrence.occurrences(dueDate: due, in: try monthWindow(2026, 5), calendar: calendar).isEmpty
        )
    }

    // MARK: - Expanding a window

    func testDailyFillsTheRestOfTheMonth() throws {
        let due = try date(2026, 5, 10)
        let dates = TaskRecurrence.interval(seconds: 86400)
            .occurrences(dueDate: due, in: try monthWindow(2026, 5), calendar: calendar)

        // The 11th through the 31st. The 10th is the real due date, which the
        // calendar already places, so it is not projected here.
        XCTAssertEqual(dates.count, 21)
        XCTAssertEqual(dates.first, try date(2026, 5, 11))
        XCTAssertEqual(dates.last, try date(2026, 5, 31))
        XCTAssertEqual(dates, dates.sorted())
    }

    func testWeeklyKeepsItsSevenDaySpacing() throws {
        let due = try date(2026, 5, 4)
        let dates = TaskRecurrence.interval(seconds: 604_800)
            .occurrences(dueDate: due, in: try monthWindow(2026, 5), calendar: calendar)

        XCTAssertEqual(dates, [try date(2026, 5, 11), try date(2026, 5, 18), try date(2026, 5, 25)])
    }

    /// What bounds the work, and why the bound is not an arbitrary cap: the
    /// calendar keys on a day and can show a task once on it, so a task
    /// repeating every second contributes one date per day rather than 86400.
    func testASubDailyRepeatCollapsesToOnePerDay() throws {
        let due = try date(2026, 5, 10)
        let dates = TaskRecurrence.interval(seconds: 1)
            .occurrences(dueDate: due, in: try monthWindow(2026, 5), calendar: calendar)

        // The 10th (just after the due time) through the 31st.
        XCTAssertEqual(dates.count, 22)
        XCTAssertEqual(Set(dates.map { calendar.startOfDay(for: $0) }).count, dates.count)
    }

    func testMonthlyProjectsOnceIntoALaterMonth() throws {
        let due = try date(2026, 1, 31)
        let dates = TaskRecurrence.monthly
            .occurrences(dueDate: due, in: try monthWindow(2026, 2), calendar: calendar)

        XCTAssertEqual(dates, [try date(2026, 2, 28)])
    }

    func testAWindowEntirelyAfterTheDueDateIsFullyPopulated() throws {
        let due = try date(2026, 5, 10)
        let dates = TaskRecurrence.interval(seconds: 86400)
            .occurrences(dueDate: due, in: try monthWindow(2026, 6), calendar: calendar)

        XCTAssertEqual(dates.count, 30)
        XCTAssertEqual(dates.first, try date(2026, 6, 1))
    }

    func testAnEmptyWindowProjectsNothing() throws {
        let due = try date(2026, 5, 10)
        let instant = try date(2026, 5, 12, 0)

        XCTAssertTrue(
            TaskRecurrence.interval(seconds: 86400)
                .occurrences(dueDate: due, in: instant ..< instant, calendar: calendar)
                .isEmpty
        )
    }
}
