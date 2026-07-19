import XCTest
@testable import mDone

final class QuickScheduleTests: XCTestCase {
    /// A fixed calendar (Gregorian, Monday-start, UTC) so date math is deterministic
    /// regardless of the test machine's locale or timezone.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// Builds a UTC date for the given components.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testTodayResolvesToStartOfToday() {
        // Wednesday 2026-06-17, 14:30
        let now = date(2026, 6, 17, 14, 30)
        XCTAssertEqual(QuickSchedule.today.resolvedDate(now: now, calendar: calendar), date(2026, 6, 17))
    }

    func testTomorrowResolvesToStartOfNextDay() {
        let now = date(2026, 6, 17, 14, 30)
        XCTAssertEqual(QuickSchedule.tomorrow.resolvedDate(now: now, calendar: calendar), date(2026, 6, 18))
    }

    func testLaterThisWeekResolvesToLastDayOfWeek() {
        // Wednesday 2026-06-17; Monday-start week ends Sunday 2026-06-21.
        let now = date(2026, 6, 17, 14, 30)
        XCTAssertEqual(QuickSchedule.laterThisWeek.resolvedDate(now: now, calendar: calendar), date(2026, 6, 21))
    }

    func testNextWeekResolvesToStartOfFollowingWeek() {
        // Wednesday 2026-06-17; next Monday is 2026-06-22.
        let now = date(2026, 6, 17, 14, 30)
        XCTAssertEqual(QuickSchedule.nextWeek.resolvedDate(now: now, calendar: calendar), date(2026, 6, 22))
    }

    func testNextMonthResolvesToFirstOfFollowingMonth() {
        let now = date(2026, 6, 17, 14, 30)
        XCTAssertEqual(QuickSchedule.nextMonth.resolvedDate(now: now, calendar: calendar), date(2026, 7, 1))
    }

    func testNextMonthRollsOverYearBoundary() {
        let now = date(2026, 12, 20)
        XCTAssertEqual(QuickSchedule.nextMonth.resolvedDate(now: now, calendar: calendar), date(2027, 1, 1))
    }

    func testResolvedDatesAreDateOnlyMidnight() throws {
        let now = date(2026, 6, 17, 9, 15)
        for option in QuickSchedule.allCases {
            let resolved = option.resolvedDate(now: now, calendar: calendar)
            let components = try calendar.dateComponents([.hour, .minute, .second], from: XCTUnwrap(resolved))
            XCTAssertEqual(components.hour, 0, "\(option.label) should land at midnight")
            XCTAssertEqual(components.minute, 0)
            XCTAssertEqual(components.second, 0)
        }
    }

    func testOptionsHideLaterThisWeekMidWeekWhenItEqualsTomorrowOrEarlier() {
        // Saturday 2026-06-20: "later this week" is Sunday 21st, which is still
        // strictly after tomorrow (Sunday 21st == tomorrow) → should be hidden.
        let now = date(2026, 6, 20, 10, 0)
        let options = QuickSchedule.options(now: now, calendar: calendar)
        XCTAssertFalse(options.contains(.laterThisWeek))
    }

    func testOptionsKeepLaterThisWeekEarlyInWeek() {
        // Monday 2026-06-15: "later this week" is Sunday 21st, well after tomorrow.
        let now = date(2026, 6, 15, 10, 0)
        let options = QuickSchedule.options(now: now, calendar: calendar)
        XCTAssertTrue(options.contains(.laterThisWeek))
        XCTAssertEqual(options.first, .today)
    }

    func testOptionsAlwaysIncludeCoreChoices() {
        let now = date(2026, 6, 17, 14, 30)
        let options = QuickSchedule.options(now: now, calendar: calendar)
        for required in [QuickSchedule.today, .tomorrow, .nextWeek, .nextMonth] {
            XCTAssertTrue(options.contains(required), "\(required.label) should always be offered")
        }
    }
}
