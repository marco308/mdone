import XCTest
@testable import mDone

final class ScheduleOptionTests: XCTestCase {
    /// A fixed calendar so results don't depend on the device locale or the
    /// stored "Start week on" preference. Monday-first, UTC.
    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    /// Builds a date at the given Y/M/D (midnight UTC) for assertions.
    private func date(_ year: Int, _ month: Int, _ day: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Reference "now": Wednesday 11 June 2026, 14:30 UTC.
    private func referenceNow(in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 14, minute: 30))!
    }

    func testEveryResultIsStartOfDay() {
        let cal = calendar()
        let now = referenceNow(in: cal)
        for option in ScheduleOption.allCases {
            let result = option.date(from: now, calendar: cal)
            let comps = cal.dateComponents([.hour, .minute, .second], from: result)
            XCTAssertEqual(comps.hour, 0, "\(option) should be midnight")
            XCTAssertEqual(comps.minute, 0)
            XCTAssertEqual(comps.second, 0)
        }
    }

    func testToday() {
        let cal = calendar()
        let result = ScheduleOption.today.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 11, in: cal))
    }

    func testTomorrow() {
        let cal = calendar()
        let result = ScheduleOption.tomorrow.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 12, in: cal))
    }

    func testThisWeekendIsUpcomingSaturday() {
        let cal = calendar()
        // Wed 11 June → Sat 13 June 2026.
        let result = ScheduleOption.thisWeekend.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 13, in: cal))
        XCTAssertEqual(cal.component(.weekday, from: result), 7)
    }

    func testThisWeekendOnSaturdayRollsToNextSaturday() throws {
        let cal = calendar()
        // Sat 13 June 2026 at noon → next Saturday 20 June.
        let saturday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12)))
        let result = ScheduleOption.thisWeekend.date(from: saturday, calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 20, in: cal))
    }

    func testNextWeekMondayStart() {
        let cal = calendar(firstWeekday: 2) // Monday
        // Week of Wed 11 June starts Mon 8 June; next week starts Mon 15 June.
        let result = ScheduleOption.nextWeek.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 15, in: cal))
        XCTAssertEqual(cal.component(.weekday, from: result), 2)
    }

    func testNextWeekHonoursSundayStart() {
        let cal = calendar(firstWeekday: 1) // Sunday
        // Week of Wed 11 June starts Sun 7 June; next week starts Sun 14 June.
        let result = ScheduleOption.nextWeek.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 6, 14, in: cal))
        XCTAssertEqual(cal.component(.weekday, from: result), 1)
    }

    func testNextMonthIsFirstOfFollowingMonth() {
        let cal = calendar()
        let result = ScheduleOption.nextMonth.date(from: referenceNow(in: cal), calendar: cal)
        XCTAssertEqual(result, date(2026, 7, 1, in: cal))
    }

    func testNextMonthWrapsYear() throws {
        let cal = calendar()
        let december = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 9)))
        let result = ScheduleOption.nextMonth.date(from: december, calendar: cal)
        XCTAssertEqual(result, date(2027, 1, 1, in: cal))
    }

    func testAllOptionsHaveLabelAndImage() {
        for option in ScheduleOption.allCases {
            XCTAssertFalse(option.label.isEmpty)
            XCTAssertFalse(option.systemImage.isEmpty)
        }
    }
}
