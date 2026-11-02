import XCTest
@testable import mDone

/// Tasks said aloud to Siri or typed into the Inbox get a due date the user
/// never typed, so the rule that picks it has to be exactly what Settings
/// promises.
final class NewTaskDueDatePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "NewTaskDueDatePreferenceTests"
    private let calendar = Calendar(identifier: .gregorian)
    private let siriKey = NewTaskDueDatePreference.siriStorageKey
    private let inboxKey = NewTaskDueDatePreference.inboxStorageKey

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

    private func dueDate(forKey key: String) -> Date? {
        NewTaskDueDatePreference.dueDate(forKey: key, now: noon, calendar: calendar, defaults: defaults)
    }

    func testDefaultsToToday() {
        XCTAssertEqual(NewTaskDueDatePreference.current(forKey: siriKey, defaults: defaults), .today)
        XCTAssertEqual(NewTaskDueDatePreference.current(forKey: inboxKey, defaults: defaults), .today)
    }

    func testSiriKeyIsUnchangedSoExistingChoicesCarryOver() {
        XCTAssertEqual(siriKey, "siriDueDate")
        XCTAssertNotEqual(siriKey, inboxKey)
    }

    func testUnknownStoredValueFallsBackToToday() {
        defaults.set("next-week", forKey: siriKey)
        XCTAssertEqual(NewTaskDueDatePreference.current(forKey: siriKey, defaults: defaults), .today)
    }

    func testTodayAtSixPMByDefault() throws {
        let c = try components(XCTUnwrap(dueDate(forKey: siriKey)))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 3, 18, 0])
    }

    func testFollowsTheDefaultDueTimeSetting() throws {
        defaults.set(DefaultDueTimePreference.nineAM.rawValue, forKey: DefaultDueTimePreference.storageKey)
        let c = try components(XCTUnwrap(dueDate(forKey: inboxKey)))
        XCTAssertEqual([c.day, c.hour, c.minute], [3, 9, 0])
    }

    func testTomorrow() throws {
        defaults.set(NewTaskDueDatePreference.tomorrow.rawValue, forKey: siriKey)
        let c = try components(XCTUnwrap(dueDate(forKey: siriKey)))
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [9, 4, 18, 0])
    }

    func testNoneGivesNoDueDate() {
        defaults.set(NewTaskDueDatePreference.none.rawValue, forKey: siriKey)
        XCTAssertNil(dueDate(forKey: siriKey))
    }

    /// #210: turning the Inbox date off must not change what Siri does, and
    /// the other way round.
    func testInboxAndSiriAreIndependent() throws {
        defaults.set(NewTaskDueDatePreference.none.rawValue, forKey: inboxKey)
        XCTAssertNil(dueDate(forKey: inboxKey))
        XCTAssertNotNil(dueDate(forKey: siriKey))

        defaults.set(NewTaskDueDatePreference.tomorrow.rawValue, forKey: siriKey)
        let c = try components(XCTUnwrap(dueDate(forKey: siriKey)))
        XCTAssertEqual(c.day, 4)
        XCTAssertNil(dueDate(forKey: inboxKey))
    }

    func testLabelsAreDistinct() {
        XCTAssertEqual(
            Set(NewTaskDueDatePreference.allCases.map(\.label)).count,
            NewTaskDueDatePreference.allCases.count
        )
    }
}
