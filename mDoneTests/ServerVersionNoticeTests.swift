import XCTest
@testable import mDone

/// The notice that a server is older than Vikunja's v2 API, which a later
/// mDone will need (#289, #290).
final class ServerVersionNoticeTests: XCTestCase {
    private let noticeSeenKey = "serverUpdateNoticeSeen"
    private var savedServerURL: String?

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        savedServerURL = AuthService.shared.getServerURL()
        AuthService.shared.saveServerURL("https://mock.vikunja.io")
        UserDefaults.standard.removeObject(forKey: noticeSeenKey)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        if let savedServerURL {
            AuthService.shared.saveServerURL(savedServerURL)
        } else {
            AuthService.shared.clearServerURL()
        }
        UserDefaults.standard.removeObject(forKey: noticeSeenKey)
        super.tearDown()
    }

    // MARK: - Parsing

    func testParsesReleaseAndUnstableVersionStrings() {
        XCTAssertEqual(VikunjaVersion("v2.4.0"), VikunjaVersion(major: 2, minor: 4, patch: 0))
        XCTAssertEqual(VikunjaVersion("2.7.1"), VikunjaVersion(major: 2, minor: 7, patch: 1))
        XCTAssertEqual(VikunjaVersion("v0.24.6"), VikunjaVersion(major: 0, minor: 24, patch: 6))
        XCTAssertEqual(VikunjaVersion("v2.4.0-312-abcdef12"), VikunjaVersion(major: 2, minor: 4, patch: 0))
        XCTAssertEqual(VikunjaVersion("v2.5"), VikunjaVersion(major: 2, minor: 5, patch: 0))
        XCTAssertEqual(VikunjaVersion("v2.4.0").map(\.description), "2.4.0")
    }

    func testStringsWithoutAVersionNumberDoNotParse() {
        XCTAssertNil(VikunjaVersion("unstable"))
        XCTAssertNil(VikunjaVersion("dev"))
        XCTAssertNil(VikunjaVersion(""))
        XCTAssertNil(VikunjaVersion("v2"))
        XCTAssertNil(VikunjaVersion("v2..1"))
    }

    func testOrdersByMajorThenMinorThenPatch() throws {
        let v2API = VikunjaVersion.firstWithAPIv2
        XCTAssertLessThan(try XCTUnwrap(VikunjaVersion("v2.3.9")), v2API)
        XCTAssertLessThan(try XCTUnwrap(VikunjaVersion("v1.10.0")), v2API)
        XCTAssertLessThan(try XCTUnwrap(VikunjaVersion("v0.24.6")), v2API)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(VikunjaVersion("v2.4.0")), v2API)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(VikunjaVersion("v2.10.0")), v2API)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(VikunjaVersion("v3.0.0")), v2API)
    }

    // MARK: - AppState

    @MainActor
    private func signedInAppState(serverReports body: String, status: Int = 200) -> AppState {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: status, url: request.url), Data(body.utf8))
        }
        let appState = AppState(serverInfoService: ServerInfoService(apiClient: MockURLProtocol.mockClient()))
        appState.isAuthenticated = true
        return appState
    }

    @MainActor
    func testOldServerRaisesTheNoticeOnce() async {
        let appState = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await appState.loadServerVersionIfNeeded()

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.url?.path), [VikunjaAPI.path("/info")])
        XCTAssertEqual(appState.serverVersion, VikunjaVersion(major: 2, minor: 3, patch: 0))
        XCTAssertTrue(appState.serverNeedsUpdate)
        XCTAssertTrue(appState.showServerUpdateNotice)

        appState.acknowledgeServerUpdateNotice()
        XCTAssertFalse(appState.showServerUpdateNotice)

        // Next launch: Settings still says so, but the alert does not come back.
        let relaunched = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await relaunched.loadServerVersionIfNeeded()
        XCTAssertTrue(relaunched.serverNeedsUpdate)
        XCTAssertFalse(relaunched.showServerUpdateNotice)
    }

    @MainActor
    func testCurrentServerRaisesNothing() async {
        let appState = signedInAppState(serverReports: #"{"version": "v2.4.0"}"#)
        await appState.loadServerVersionIfNeeded()

        XCTAssertFalse(appState.serverNeedsUpdate)
        XCTAssertFalse(appState.showServerUpdateNotice)
    }

    @MainActor
    func testUnknownVersionIsNotTreatedAsOld() async {
        let appState = signedInAppState(serverReports: #"{"version": "unstable"}"#)
        await appState.loadServerVersionIfNeeded()

        XCTAssertNil(appState.serverVersion)
        XCTAssertFalse(appState.serverNeedsUpdate)
        XCTAssertFalse(appState.showServerUpdateNotice)
    }

    @MainActor
    func testFailedInfoRequestIsQuiet() async {
        let appState = signedInAppState(serverReports: "", status: 404)
        await appState.loadServerVersionIfNeeded()

        XCTAssertNil(appState.serverVersion)
        XCTAssertFalse(appState.showServerUpdateNotice)
        XCTAssertNil(appState.activeError)
    }

    @MainActor
    func testSignedOutMakesNoRequest() async {
        let appState = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        appState.isAuthenticated = false
        await appState.loadServerVersionIfNeeded()

        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
        XCTAssertNil(appState.serverVersion)
    }

    @MainActor
    func testLoggingOutForgetsTheNoticeWasSeen() async {
        let appState = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await appState.loadServerVersionIfNeeded()
        appState.acknowledgeServerUpdateNotice()

        await appState.logout()

        XCTAssertNil(appState.serverVersion)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: noticeSeenKey))
    }

    func testNoticeNamesBothVersions() {
        let message = ServerUpdateNotice.message(for: VikunjaVersion(major: 2, minor: 3, patch: 1))
        XCTAssertTrue(message.contains("2.3.1"))
        XCTAssertTrue(message.contains("2.4.0"))
    }
}
