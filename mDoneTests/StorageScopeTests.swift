import XCTest
@testable import mDone

/// Unit tests must never read or write the stores a real login lives in, and
/// a Debug build must not share an app group with the shipped app.
final class StorageScopeTests: XCTestCase {
    func testTheTestHostIsRecognised() {
        XCTAssertTrue(StorageScope.isHostingUnitTests)
    }

    func testServerURLStaysOutOfTheAppsOwnDefaults() {
        let key = "com.mdone.serverURL"
        let before = UserDefaults.standard.string(forKey: key)
        addTeardownBlock { AuthService.shared.clearServerURL() }

        AuthService.shared.saveServerURL("https://scope.example.com")

        XCTAssertEqual(AuthService.shared.getServerURL(), "https://scope.example.com")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), before, "The host app's own login was touched")
    }

    func testSharedDefaultsAreNotTheAppGroup() {
        let key = "com.mdone.tests.scopeProbe"
        addTeardownBlock { SharedKeys.sharedDefaults.removeObject(forKey: key) }

        SharedKeys.sharedDefaults.set("probe", forKey: key)

        XCTAssertEqual(FocusConstants.sharedDefaults.string(forKey: key), "probe")
        XCTAssertNil(UserDefaults(suiteName: StorageScope.appGroupID)?.string(forKey: key))
    }

    func testKeychainAccountsAreSetApart() {
        XCTAssertEqual(StorageScope.keychainAccount("com.mdone.apiToken"), "unit-tests.com.mdone.apiToken")
    }

    /// `project.yml` derives the entitlements' group from the same pair of
    /// settings as the bundle ID, so the code's group has to follow the bundle.
    func testAppGroupFollowsTheBundleIdentifier() throws {
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertEqual(StorageScope.appGroupID, "group." + bundleID)
    }

    /// A Debug build is mDone Dev. The prefix is not checked, because a
    /// contributor's `Config/Local.xcconfig` may replace `com.mdone` (#154).
    func testDebugBuildsAreNotTheShippedApp() throws {
        #if DEBUG
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue(bundleID.hasSuffix(".app.dev"), bundleID)
        XCTAssertNotEqual(bundleID, "com.mdone.app")
        XCTAssertNotEqual(StorageScope.appGroupID, "group.com.mdone.app")
        #endif
    }

    /// The group comes from the build's Info.plist, where it is
    /// `$(MDONE_APP_GROUP)`, the same setting the entitlements use.
    func testAppGroupComesFromTheBuild() {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: StorageScope.appGroupInfoKey) as? String
        XCTAssertEqual(StorageScope.appGroupID, fromPlist)
    }

    func testAppGroupIsReadFromTheInfoDictionary() {
        let info: [String: Any] = [
            "MDoneAppGroup": "group.com.example.mdone.app.dev",
            "CFBundleIdentifier": "com.example.mdone.app.dev.widgets",
        ]
        XCTAssertEqual(StorageScope.resolveAppGroupID(from: info), "group.com.example.mdone.app.dev")
    }

    /// Without the key, or with a value Xcode did not expand, the group must
    /// never be the shipped app's.
    func testAMissingAppGroupNeverFallsBackToTheShippedApp() {
        let unexpanded: [String: Any] = ["MDoneAppGroup": "$(MDONE_APP_GROUP)", "CFBundleIdentifier": "com.mdone.app"]
        for info in [nil, [:], ["CFBundleIdentifier": "com.mdone.app"], unexpanded] as [[String: Any]?] {
            let group = StorageScope.resolveAppGroupID(from: info)
            XCTAssertNotEqual(group, "group.com.mdone.app")
            XCTAssertNotEqual(group, "group.com.mdone.app.dev")
        }
    }
}
