import XCTest
@testable import mDone

final class DueDateDefaultsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let comps = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        return calendar.date(from: comps)!
    }

    func testAppliesDefaultWhenSourceIsMidnight() {
        let midnight = date(2026, 5, 20, 0, 0)
        let result = DueDateDefaults.apply(defaultMinutes: 18 * 60, to: midnight, calendar: calendar)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 0)
    }

    func testLeavesTimedDateUnchanged() {
        let timed = date(2026, 5, 20, 9, 30)
        let result = DueDateDefaults.apply(defaultMinutes: 18 * 60, to: timed, calendar: calendar)
        XCTAssertEqual(result, timed)
    }

    func testRespectsCustomMinutes() {
        let midnight = date(2026, 5, 20)
        let result = DueDateDefaults.apply(defaultMinutes: 23 * 60 + 59, to: midnight, calendar: calendar)
        let comps = calendar.dateComponents([.hour, .minute], from: result)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 59)
    }

    func testClampsOutOfRangeMinutes() {
        let midnight = date(2026, 5, 20)
        let tooHigh = DueDateDefaults.apply(defaultMinutes: 9999, to: midnight, calendar: calendar)
        let high = calendar.dateComponents([.hour, .minute], from: tooHigh)
        XCTAssertEqual(high.hour, 23)
        XCTAssertEqual(high.minute, 59)

        let negative = DueDateDefaults.apply(defaultMinutes: -10, to: midnight, calendar: calendar)
        let low = calendar.dateComponents([.hour, .minute], from: negative)
        XCTAssertEqual(low.hour, 0)
        XCTAssertEqual(low.minute, 0)
    }

    func testKeepsCalendarDay() {
        // Default time set to 23:59 must not bump the date forward.
        let midnight = date(2026, 5, 20)
        let result = DueDateDefaults.apply(defaultMinutes: 23 * 60 + 59, to: midnight, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: result), 20)
    }
}
