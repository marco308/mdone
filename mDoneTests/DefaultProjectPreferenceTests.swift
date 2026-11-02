import XCTest
@testable import mDone

/// #210: a task added from the Inbox landed in whichever project happened to
/// sort first. The pick now comes from Settings, falling back to the project
/// Vikunja names "Inbox".
final class DefaultProjectPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DefaultProjectPreferenceTests"

    private let work = Project(id: 3, title: "Work")
    private let inbox = Project(id: 7, title: "Inbox")
    private let home = Project(id: 9, title: "Home")

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

    func testUnsetIsAutomatic() {
        XCTAssertNil(DefaultProjectPreference.storedProjectId(defaults: defaults))
    }

    func testAutomaticPrefersTheInboxProject() {
        let picked = DefaultProjectPreference.resolve(in: [work, inbox, home], defaults: defaults)
        XCTAssertEqual(picked?.id, inbox.id)
    }

    func testAutomaticMatchesInboxIgnoringCaseAndSpaces() {
        let lower = Project(id: 11, title: " inbox ")
        let picked = DefaultProjectPreference.resolve(in: [work, lower], defaults: defaults)
        XCTAssertEqual(picked?.id, lower.id)
    }

    func testAutomaticFallsBackToFirstProjectWithoutAnInbox() {
        let picked = DefaultProjectPreference.resolve(in: [work, home], defaults: defaults)
        XCTAssertEqual(picked?.id, work.id)
    }

    func testUserPickWins() {
        defaults.set(Int(home.id), forKey: DefaultProjectPreference.storageKey)
        XCTAssertEqual(DefaultProjectPreference.storedProjectId(defaults: defaults), home.id)
        let picked = DefaultProjectPreference.resolve(in: [work, inbox, home], defaults: defaults)
        XCTAssertEqual(picked?.id, home.id)
    }

    func testMissingPickFallsBackToAutomatic() {
        defaults.set(42, forKey: DefaultProjectPreference.storageKey)
        let picked = DefaultProjectPreference.resolve(in: [work, inbox], defaults: defaults)
        XCTAssertEqual(picked?.id, inbox.id)
    }

    /// Vikunja's saved filters and pseudo-projects ride along in
    /// `AppState.projects` with negative ids, and there is no
    /// `PUT /projects/-2/tasks`, so they can never be the default.
    func testPseudoProjectsAreNeverSelectable() {
        let savedFilter = Project(id: -2, title: "My Open Tasks")
        let inboxFilter = Project(id: -3, title: "Inbox")
        XCTAssertEqual(
            DefaultProjectPreference.selectable(from: [savedFilter, inboxFilter, work]).map(\.id),
            [work.id]
        )
        let picked = DefaultProjectPreference.resolve(in: [savedFilter, inboxFilter, work], defaults: defaults)
        XCTAssertEqual(picked?.id, work.id)
    }

    func testStoredPseudoProjectIdReadsAsAutomatic() {
        defaults.set(-2, forKey: DefaultProjectPreference.storageKey)
        XCTAssertNil(DefaultProjectPreference.storedProjectId(defaults: defaults))
        let picked = DefaultProjectPreference.resolve(
            in: [Project(id: -2, title: "My Open Tasks"), inbox, work],
            defaults: defaults
        )
        XCTAssertEqual(picked?.id, inbox.id)
    }

    func testOnlyPseudoProjectsGivesNil() {
        let picked = DefaultProjectPreference.resolve(in: [Project(id: -2, title: "My Open Tasks")], defaults: defaults)
        XCTAssertNil(picked)
    }

    func testNoProjectsGivesNil() {
        XCTAssertNil(DefaultProjectPreference.resolve(in: [], defaults: defaults))
    }
}
