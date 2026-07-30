import XCTest
@testable import mDone

final class AllDayEventPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AllDayEventPreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makePreference() -> AllDayEventPreference {
        AllDayEventPreference(defaults: defaults)
    }

    private func event(_ id: String, isAllDay: Bool) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Event \(id)",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            isAllDay: isAllDay,
            calendarIdentifier: "work"
        )
    }

    // MARK: - Default (missing key)

    func testMissingKeyShowsAllDayEvents() {
        let preference = makePreference()
        XCTAssertFalse(preference.hidesAllDayEvents)

        let events = [event("1", isAllDay: true), event("2", isAllDay: false)]
        XCTAssertEqual(preference.visibleEvents(events).map(\.id), ["1", "2"])
    }

    func testExplicitFalseShowsAllDayEvents() {
        defaults.set(false, forKey: AllDayEventPreference.storageKey)
        let preference = makePreference()
        XCTAssertFalse(preference.hidesAllDayEvents)

        let events = [event("1", isAllDay: true), event("2", isAllDay: false)]
        XCTAssertEqual(preference.visibleEvents(events).map(\.id), ["1", "2"])
    }

    // MARK: - Hidden

    func testHiddenFiltersOnlyAllDayEvents() {
        defaults.set(true, forKey: AllDayEventPreference.storageKey)
        let preference = makePreference()
        XCTAssertTrue(preference.hidesAllDayEvents)

        let events = [
            event("1", isAllDay: true),
            event("2", isAllDay: false),
            event("3", isAllDay: true),
            event("4", isAllDay: false)
        ]
        XCTAssertEqual(preference.visibleEvents(events).map(\.id), ["2", "4"])
    }

    func testHiddenWithOnlyTimedEventsKeepsAll() {
        defaults.set(true, forKey: AllDayEventPreference.storageKey)
        let preference = makePreference()

        let events = [event("1", isAllDay: false), event("2", isAllDay: false)]
        XCTAssertEqual(preference.visibleEvents(events).map(\.id), ["1", "2"])
    }

    func testHiddenWithEmptyInputReturnsEmpty() {
        defaults.set(true, forKey: AllDayEventPreference.storageKey)
        let preference = makePreference()
        XCTAssertTrue(preference.visibleEvents([]).isEmpty)
    }
}
