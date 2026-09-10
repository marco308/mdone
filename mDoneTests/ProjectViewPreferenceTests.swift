import XCTest
@testable import mDone

/// Which view a project opens in (#184): the default from Settings, the
/// per-project choice that overrides it, and what happens to values we did
/// not write.
final class ProjectViewPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ProjectViewPreferenceTests"

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

    // MARK: - Defaults

    func testNothingStoredOpensTheList() {
        XCTAssertEqual(ProjectViewPreference.defaultMode(defaults: defaults), .list)
        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .list)
    }

    func testDefaultAppliesToEveryProjectWithoutAChoice() {
        defaults.set(ProjectViewMode.board.rawValue, forKey: ProjectViewPreference.defaultStorageKey)

        XCTAssertEqual(ProjectViewPreference.defaultMode(defaults: defaults), .board)
        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .board)
        XCTAssertEqual(ProjectViewPreference.mode(for: 8, defaults: defaults), .board)
    }

    // MARK: - Per project

    func testSavedChoiceIsRememberedForThatProjectAlone() {
        ProjectViewPreference.save(.board, for: 7, defaults: defaults)

        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .board)
        XCTAssertEqual(ProjectViewPreference.mode(for: 8, defaults: defaults), .list)
    }

    func testProjectChoiceOverridesTheDefault() {
        defaults.set(ProjectViewMode.board.rawValue, forKey: ProjectViewPreference.defaultStorageKey)
        ProjectViewPreference.save(.list, for: 7, defaults: defaults)

        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .list)
        XCTAssertEqual(ProjectViewPreference.mode(for: 8, defaults: defaults), .board)
    }

    func testClearingPutsTheProjectBackOnTheDefault() {
        defaults.set(ProjectViewMode.board.rawValue, forKey: ProjectViewPreference.defaultStorageKey)
        ProjectViewPreference.save(.list, for: 7, defaults: defaults)
        ProjectViewPreference.clear(for: 7, defaults: defaults)

        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .board)
    }

    func testEachProjectGetsItsOwnKey() {
        XCTAssertNotEqual(
            ProjectViewPreference.projectStorageKey(for: 7),
            ProjectViewPreference.projectStorageKey(for: 8)
        )
        XCTAssertNotEqual(ProjectViewPreference.projectStorageKey(for: 7), ProjectViewPreference.defaultStorageKey)
    }

    // MARK: - Unrecognised values

    func testUnrecognisedStoredValuesFallBack() {
        defaults.set("gantt", forKey: ProjectViewPreference.defaultStorageKey)
        XCTAssertEqual(ProjectViewPreference.defaultMode(defaults: defaults), .list)

        defaults.set(ProjectViewMode.board.rawValue, forKey: ProjectViewPreference.defaultStorageKey)
        defaults.set("gantt", forKey: ProjectViewPreference.projectStorageKey(for: 7))
        XCTAssertEqual(ProjectViewPreference.mode(for: 7, defaults: defaults), .board)
    }

    // MARK: - Mode

    func testEveryModeHasALabelAndAStableRawValue() {
        XCTAssertEqual(ProjectViewMode.allCases.map(\.rawValue), ["list", "board"])
        for mode in ProjectViewMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }
}
