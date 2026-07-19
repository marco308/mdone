import XCTest
@testable import mDone

/// Tests for the keychain-backed shared token store, including the one-shot
/// migration away from the pre-1.6.3 cleartext copy in the app group defaults.
final class SharedTokenStoreTests: XCTestCase {
    private var savedToken: String?

    override func setUp() {
        super.setUp()
        // Preserve whatever real token might be stored on this simulator and
        // start each test from a clean slate.
        savedToken = SharedTokenStore.get()
        SharedTokenStore.delete()
    }

    override func tearDown() {
        if let savedToken {
            SharedTokenStore.save(savedToken)
        } else {
            SharedTokenStore.delete()
        }
        super.tearDown()
    }

    func testGetReturnsNilWhenEmpty() {
        XCTAssertNil(SharedTokenStore.get())
    }

    func testSaveThenGetRoundTrip() {
        XCTAssertTrue(SharedTokenStore.save("tk_test_roundtrip"), "Keychain write should succeed")
        XCTAssertEqual(SharedTokenStore.get(), "tk_test_roundtrip")
    }

    func testSaveScrubsLegacyDefaultsCopyOnSuccess() {
        SharedKeys.sharedDefaults.set("tk_old", forKey: SharedKeys.apiTokenKey)

        XCTAssertTrue(SharedTokenStore.save("tk_new"))

        XCTAssertNil(
            SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey),
            "A successful keychain write should remove the cleartext copy"
        )
        XCTAssertEqual(SharedTokenStore.get(), "tk_new")
    }

    func testSaveOverwritesPreviousToken() {
        SharedTokenStore.save("tk_first")
        SharedTokenStore.save("tk_second")
        XCTAssertEqual(SharedTokenStore.get(), "tk_second")
    }

    func testDeleteRemovesToken() {
        SharedTokenStore.save("tk_gone")
        SharedTokenStore.delete()
        XCTAssertNil(SharedTokenStore.get())
    }

    func testMigratesLegacyDefaultsToken() {
        SharedKeys.sharedDefaults.set("tk_legacy", forKey: SharedKeys.apiTokenKey)

        XCTAssertEqual(SharedTokenStore.get(), "tk_legacy")
        XCTAssertNil(
            SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey),
            "Migration should scrub the cleartext copy from the app group defaults"
        )
        XCTAssertEqual(SharedTokenStore.get(), "tk_legacy", "Token should now be served from the keychain")
    }

    func testDeleteScrubsLegacyDefaultsCopy() {
        SharedKeys.sharedDefaults.set("tk_legacy", forKey: SharedKeys.apiTokenKey)

        SharedTokenStore.delete()

        XCTAssertNil(SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey))
        XCTAssertNil(SharedTokenStore.get())
    }
}
