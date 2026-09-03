import XCTest
@testable import mDone

/// Tasks said aloud to Siri get a due date the user never typed, so the rule
/// that picks it has to be exactly what Settings promises.
final class SiriDueDatePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SiriDueDatePreferenceTests"
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12, minute: 30))!
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testDefaultsToToday() {
        XCTAssertEqual(SiriDueDatePreference.current(defaults: defaults), .today)
    }

    func testUnknownStoredValueFallsBackToToday() {
        defaults.set("next-week", forKey: SiriDueDatePreference.storageKey)
        XCTAssertEqual(SiriDueDatePreference.current(defaults: defaults), .today)
    }

    func testTodayAtSixPMByDefault() throws {
        let due = try XCTUnwrap(SiriDueDatePreference.dueDate(now: noon, calendar: calendar, defaults: defaults))
        let c = components(due)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 3, 18, 0])
    }

    func testFollowsTheDefaultDueTimeSetting() throws {
        defaults.set(DefaultDueTimePreference.nineAM.rawValue, forKey: DefaultDueTimePreference.storageKey)
        let due = try XCTUnwrap(SiriDueDatePreference.dueDate(now: noon, calendar: calendar, defaults: defaults))
        let c = components(due)
        XCTAssertEqual([c.day, c.hour, c.minute], [3, 9, 0])
    }

    func testTomorrow() throws {
        defaults.set(SiriDueDatePreference.tomorrow.rawValue, forKey: SiriDueDatePreference.storageKey)
        let due = try XCTUnwrap(SiriDueDatePreference.dueDate(now: noon, calendar: calendar, defaults: defaults))
        let c = components(due)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [9, 4, 18, 0])
    }

    func testNoneGivesNoDueDate() {
        defaults.set(SiriDueDatePreference.none.rawValue, forKey: SiriDueDatePreference.storageKey)
        XCTAssertNil(SiriDueDatePreference.dueDate(now: noon, calendar: calendar, defaults: defaults))
    }

    func testLabelsAreDistinct() {
        XCTAssertEqual(Set(SiriDueDatePreference.allCases.map(\.label)).count, SiriDueDatePreference.allCases.count)
    }
}
