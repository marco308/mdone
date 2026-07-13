import XCTest
@testable import mDone

final class DefaultDueTimePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DefaultDueTimePreferenceTests"

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

    func testCurrentFallsBackToSixPMWhenUnset() {
        XCTAssertEqual(DefaultDueTimePreference.current(defaults: defaults), .sixPM)
    }

    func testCurrentRespectsStoredValue() {
        defaults.set(DefaultDueTimePreference.noon.rawValue, forKey: DefaultDueTimePreference.storageKey)
        XCTAssertEqual(DefaultDueTimePreference.current(defaults: defaults), .noon)
    }

    func testCurrentFallsBackWhenStoredValueIsCorrupted() {
        // Raw values not in the enum (e.g. a leftover value from an older
        // version of the picker, or a hand-edited defaults plist) must not
        // crash or produce an invalid hour/minute via the raw-value math.
        defaults.set(-1, forKey: DefaultDueTimePreference.storageKey)
        XCTAssertEqual(DefaultDueTimePreference.current(defaults: defaults), .sixPM)

        defaults.set(9999, forKey: DefaultDueTimePreference.storageKey)
        XCTAssertEqual(DefaultDueTimePreference.current(defaults: defaults), .sixPM)
    }

    func testApplyReplacesTimeWithSixPMByDefault() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = 0
        components.minute = 0
        let calendar = Calendar(identifier: .gregorian)
        let midnight = try XCTUnwrap(calendar.date(from: components))

        let result = DefaultDueTimePreference.apply(to: midnight, calendar: calendar, defaults: defaults)
        let resultComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)

        XCTAssertEqual(resultComponents.year, 2026)
        XCTAssertEqual(resultComponents.month, 5)
        XCTAssertEqual(resultComponents.day, 21)
        XCTAssertEqual(resultComponents.hour, 18)
        XCTAssertEqual(resultComponents.minute, 0)
    }

    func testApplyHonoursStoredEndOfDay() throws {
        defaults.set(DefaultDueTimePreference.endOfDay.rawValue, forKey: DefaultDueTimePreference.storageKey)

        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 21
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: components))

        let result = DefaultDueTimePreference.apply(to: date, calendar: calendar, defaults: defaults)
        let resultComponents = calendar.dateComponents([.hour, .minute], from: result)

        XCTAssertEqual(resultComponents.hour, 23)
        XCTAssertEqual(resultComponents.minute, 59)
    }

    func testApplyDoesNotShiftTheCalendarDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        let result = DefaultDueTimePreference.apply(to: now, calendar: calendar, defaults: defaults)

        XCTAssertEqual(
            calendar.startOfDay(for: result),
            calendar.startOfDay(for: now),
            "Applying the default time must not roll over to a different day."
        )
    }
}
