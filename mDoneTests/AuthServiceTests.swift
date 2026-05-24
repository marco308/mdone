import XCTest
@testable import mDone

/// Round-trip tests for AuthService, focused on the refresh-token storage
/// and the clearSession/clearAll distinction added for issue #80.
///
/// AuthService writes the access token and refresh token to the keychain
/// and the server URL to UserDefaults. The test bundle has a real keychain
/// to talk to in the simulator, so we make sure to leave nothing behind.
final class AuthServiceTests: XCTestCase {
    private let svc = AuthService.shared

    override func setUp() {
        super.setUp()
        svc.clearAll()
    }

    override func tearDown() {
        svc.clearAll()
        super.tearDown()
    }

    func testTokenRoundTrip() {
        svc.saveToken("jwt-abc")
        XCTAssertEqual(svc.getToken(), "jwt-abc")

        svc.deleteToken()
        XCTAssertNil(svc.getToken())
    }

    func testRefreshTokenRoundTrip() {
        svc.saveRefreshToken("refresh-xyz")
        XCTAssertEqual(svc.getRefreshToken(), "refresh-xyz")

        svc.deleteRefreshToken()
        XCTAssertNil(svc.getRefreshToken())
    }

    func testSaveRefreshTokenOverwritesPrevious() {
        svc.saveRefreshToken("first")
        svc.saveRefreshToken("second")
        XCTAssertEqual(svc.getRefreshToken(), "second")
    }

    func testRefreshTokenIsNotMixedUpWithAccessToken() {
        svc.saveToken("access-1")
        svc.saveRefreshToken("refresh-1")
        XCTAssertEqual(svc.getToken(), "access-1")
        XCTAssertEqual(svc.getRefreshToken(), "refresh-1")

        // Deleting one must not delete the other.
        svc.deleteToken()
        XCTAssertNil(svc.getToken())
        XCTAssertEqual(svc.getRefreshToken(), "refresh-1")
    }

    func testClearSessionDropsTokensButKeepsServerURL() {
        svc.saveServerURL("https://example.com")
        svc.saveToken("jwt")
        svc.saveRefreshToken("refresh")

        svc.clearSession()

        XCTAssertEqual(svc.getServerURL(), "https://example.com",
                       "expireSession() relies on the server URL surviving so users don't have to retype it")
        XCTAssertNil(svc.getToken())
        XCTAssertNil(svc.getRefreshToken())
    }

    func testClearAllWipesEverything() {
        svc.saveServerURL("https://example.com")
        svc.saveToken("jwt")
        svc.saveRefreshToken("refresh")

        svc.clearAll()

        XCTAssertNil(svc.getServerURL())
        XCTAssertNil(svc.getToken())
        XCTAssertNil(svc.getRefreshToken())
    }

    func testIsAuthenticatedRequiresBothURLAndToken() {
        XCTAssertFalse(svc.isAuthenticated())

        svc.saveServerURL("https://example.com")
        XCTAssertFalse(svc.isAuthenticated())

        svc.saveToken("jwt")
        XCTAssertTrue(svc.isAuthenticated())

        svc.deleteToken()
        XCTAssertFalse(svc.isAuthenticated())
    }
}
