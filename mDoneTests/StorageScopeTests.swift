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

    func testDebugBuildsAreNotTheShippedApp() {
        #if DEBUG
        XCTAssertEqual(StorageScope.appGroupID, "group.com.mdone.app.dev")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.mdone.app.dev")
        #endif
    }
}
