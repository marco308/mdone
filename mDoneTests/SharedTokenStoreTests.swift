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

    #if os(macOS)
    // MARK: - Mac widget migration (#240)

    func testSaveMovesPreWidgetMacItemIntoSharedKeychain() throws {
        var seed = SharedTokenStore.legacyMacQuery
        seed[kSecValueData as String] = Data("tk_old_mac".utf8)
        XCTAssertEqual(SecItemAdd(seed as CFDictionary, nil), errSecSuccess)

        XCTAssertTrue(SharedTokenStore.save("tk_new_mac"))
        XCTAssertEqual(SharedTokenStore.get(), "tk_new_mac")

        // Ad-hoc signed hosts (CI) have no data protection keychain, so there
        // the old item is the store itself rather than a leftover.
        try XCTSkipUnless(Self.sharedKeychainAvailable, "Needs a team-signed test host")
        XCTAssertEqual(
            legacyMacItemStatus(),
            errSecItemNotFound,
            "Once the shared item is written the pre-#240 copy should be gone"
        )
    }

    func testDeleteRemovesPreWidgetMacItem() {
        var seed = SharedTokenStore.legacyMacQuery
        seed[kSecValueData as String] = Data("tk_old_mac".utf8)
        SecItemAdd(seed as CFDictionary, nil)

        SharedTokenStore.delete()

        XCTAssertEqual(legacyMacItemStatus(), errSecItemNotFound)
        XCTAssertNil(SharedTokenStore.get())
    }

    private func legacyMacItemStatus() -> OSStatus {
        SecItemCopyMatching(SharedTokenStore.legacyMacQuery as CFDictionary, nil)
    }

    private static var sharedKeychainAvailable: Bool {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.mdone.tests.keychainProbe",
            kSecAttrAccessGroup as String: SharedKeys.appGroupID,
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemCopyMatching(probe as CFDictionary, nil) != errSecMissingEntitlement
    }
    #endif
}
