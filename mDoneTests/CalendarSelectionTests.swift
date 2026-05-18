import XCTest
@testable import mDone

final class CalendarSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CalendarSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> HiddenCalendarStore {
        HiddenCalendarStore(defaults: defaults)
    }

    private func event(_ id: String, calendar: String) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Event \(id)",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            calendarIdentifier: calendar
        )
    }

    // MARK: - Defaults / empty state

    func testEmptyStoreHidesNothing() {
        let store = makeStore()
        XCTAssertTrue(store.hiddenIdentifiers.isEmpty)
        XCTAssertFalse(store.isHidden("work"))
    }

    func testVisibleEventsReturnsAllWhenNothingHidden() {
        let store = makeStore()
        let events = [event("1", calendar: "work"), event("2", calendar: "home")]
        XCTAssertEqual(store.visibleEvents(events).map(\.id), ["1", "2"])
    }

    // MARK: - setHidden

    func testSetHiddenPersistsAndFilters() {
        let store = makeStore()
        store.setHidden(true, for: "work")

        XCTAssertTrue(store.isHidden("work"))
        XCTAssertEqual(store.hiddenIdentifiers, ["work"])

        let events = [event("1", calendar: "work"), event("2", calendar: "home")]
        XCTAssertEqual(store.visibleEvents(events).map(\.id), ["2"])
    }

    func testSetHiddenFalseUnhides() {
        let store = makeStore()
        store.setHidden(true, for: "work")
        store.setHidden(false, for: "work")

        XCTAssertFalse(store.isHidden("work"))
        XCTAssertTrue(store.hiddenIdentifiers.isEmpty)
    }

    func testSetHiddenIsIdempotent() {
        let store = makeStore()
        store.setHidden(true, for: "work")
        store.setHidden(true, for: "work")
        XCTAssertEqual(store.hiddenIdentifiers, ["work"])
    }

    func testHiddenSetSurvivesAcrossStoreInstances() {
        makeStore().setHidden(true, for: "shared")
        // A fresh store reading the same defaults sees the persisted value.
        XCTAssertTrue(makeStore().isHidden("shared"))
    }

    // MARK: - replace

    func testReplaceSetsEntireSet() {
        let store = makeStore()
        store.setHidden(true, for: "work")
        store.replace(with: ["a", "b"])
        XCTAssertEqual(store.hiddenIdentifiers, ["a", "b"])
    }

    func testReplaceWithEmptyClearsStorage() {
        let store = makeStore()
        store.replace(with: ["a", "b"])
        store.replace(with: [])
        XCTAssertTrue(store.hiddenIdentifiers.isEmpty)
        XCTAssertNil(defaults.array(forKey: HiddenCalendarStore.storageKey))
    }

    // MARK: - prune

    func testPruneDropsStaleIdentifiers() {
        let store = makeStore()
        store.replace(with: ["work", "stale", "home"])
        store.prune(toExisting: ["work", "home"])
        XCTAssertEqual(store.hiddenIdentifiers, ["home", "work"])
    }

    func testPruneKeepsAllWhenAllStillExist() {
        let store = makeStore()
        store.replace(with: ["work", "home"])
        store.prune(toExisting: ["work", "home", "extra"])
        XCTAssertEqual(store.hiddenIdentifiers, ["home", "work"])
    }

    func testPruneOnEmptyStoreIsNoOp() {
        let store = makeStore()
        store.prune(toExisting: ["work"])
        XCTAssertTrue(store.hiddenIdentifiers.isEmpty)
    }

    // MARK: - visibleEvents filtering

    func testVisibleEventsFiltersMultipleHiddenCalendars() {
        let store = makeStore()
        store.replace(with: ["work", "spam"])
        let events = [
            event("1", calendar: "work"),
            event("2", calendar: "home"),
            event("3", calendar: "spam"),
            event("4", calendar: "home")
        ]
        XCTAssertEqual(store.visibleEvents(events).map(\.id), ["2", "4"])
    }

    func testVisibleEventsKeepsEmptyCalendarIdentifierUnlessHidden() {
        let store = makeStore()
        store.setHidden(true, for: "work")
        let events = [event("1", calendar: ""), event("2", calendar: "work")]
        XCTAssertEqual(store.visibleEvents(events).map(\.id), ["1"])
    }

    // MARK: - CalendarInfo

    func testCalendarInfoEqualityByIdAndTitle() {
        let a = CalendarInfo(id: "x", title: "Work")
        let b = CalendarInfo(id: "x", title: "Work")
        let c = CalendarInfo(id: "x", title: "Renamed")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - CalendarEvent memberwise init

    func testCalendarEventMemberwiseInitAndIdentity() {
        let e1 = event("evt", calendar: "work")
        let e2 = event("evt", calendar: "home")
        XCTAssertEqual(e1.calendarIdentifier, "work")
        XCTAssertEqual(e1.title, "Event evt")
        // Hashable identity is by event id only.
        XCTAssertEqual(e1, e2)
        XCTAssertEqual(Set([e1, e2]).count, 1)
    }
}
