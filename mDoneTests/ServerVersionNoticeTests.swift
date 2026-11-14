import XCTest
@testable import mDone

/// What happens when a server is older than Vikunja's v2 API, the only one
/// mDone speaks: sign-in refuses it, and someone already signed in is told
/// why nothing works (#290, #291).
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
        if registeredGlobally {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            registeredGlobally = false
        }
        super.tearDown()
    }

    private var registeredGlobally = false

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
    func testOldServerRaisesTheNoticeOncePerLaunch() async {
        let appState = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await appState.loadServerVersionIfNeeded()

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.url?.path), [VikunjaAPI.path("/info")])
        XCTAssertEqual(appState.serverVersion, VikunjaVersion(major: 2, minor: 3, patch: 0))
        XCTAssertTrue(appState.serverNeedsUpdate)
        XCTAssertTrue(appState.showServerUpdateNotice)

        appState.acknowledgeServerUpdateNotice()
        XCTAssertFalse(appState.showServerUpdateNotice)

        // Dismissed for this launch: asking again makes no request and stays quiet.
        await appState.loadServerVersionIfNeeded()
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
        XCTAssertFalse(appState.showServerUpdateNotice)
        XCTAssertTrue(appState.serverNeedsUpdate, "Settings keeps saying so")

        // Next launch: nothing works against this server, so the alert comes back.
        let relaunched = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await relaunched.loadServerVersionIfNeeded()
        XCTAssertTrue(relaunched.serverNeedsUpdate)
        XCTAssertTrue(relaunched.showServerUpdateNotice)
    }

    /// The flag #290 persisted is no longer read: having dismissed the old
    /// one-time notice must not silence the alert now that the app is v2-only.
    @MainActor
    func testFlagLeftByTheOneTimeNoticeDoesNotSilenceTheAlert() async {
        UserDefaults.standard.set(true, forKey: noticeSeenKey)
        let appState = signedInAppState(serverReports: #"{"version": "v2.3.0"}"#)
        await appState.loadServerVersionIfNeeded()

        XCTAssertTrue(appState.showServerUpdateNotice)
    }

    /// A real pre-2.4.0 server has no `/api/v2/info`, so the version arrives
    /// through the v1 fallback.
    @MainActor
    func testOldServerIsRecognisedThroughTheV1Info() async {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == VikunjaAPI.path("/info") {
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                Data(#"{"version": "v0.24.6"}"#.utf8)
            )
        }
        let appState = AppState(serverInfoService: ServerInfoService(apiClient: MockURLProtocol.mockClient()))
        appState.isAuthenticated = true

        await appState.loadServerVersionIfNeeded()

        XCTAssertEqual(appState.serverVersion, VikunjaVersion(major: 0, minor: 24, patch: 6))
        XCTAssertTrue(appState.showServerUpdateNotice)
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

    func testNoticeForAnUnknownVersionStillNamesTheRequirement() {
        let message = ServerUpdateNotice.message(for: nil)
        XCTAssertTrue(message.contains("2.4.0"))
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: - Sign-in refuses an old server (#291)

    /// `completeLogin` talks to `APIClient.shared`, which is on
    /// `URLSession.shared`. Registering the mock globally is what lets these
    /// tests see, and answer, those requests.
    @MainActor
    private func loginAppState(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AppState {
        URLProtocol.registerClass(MockURLProtocol.self)
        registeredGlobally = true
        MockURLProtocol.requestHandler = handler
        addTeardownBlock {
            await APIClient.shared.clearCredentials()
        }
        return AppState(serverInfoService: ServerInfoService(apiClient: MockURLProtocol.mockClient()))
    }

    private static func respond(_ status: Int, _ body: String, to request: URLRequest) -> (HTTPURLResponse, Data) {
        (MockURLProtocol.makeResponse(statusCode: status, url: request.url), Data(body.utf8))
    }

    private var capturedPaths: [String] {
        MockURLProtocol.capturedRequests.compactMap { $0.url?.path }
    }

    @MainActor
    func testPasswordLoginRefusesAnOldServerBeforeSendingCredentials() async {
        let appState = loginAppState { request in
            if request.url?.path == VikunjaAPI.path("/info") {
                return Self.respond(404, "", to: request)
            }
            return Self.respond(200, #"{"version": "v2.3.0"}"#, to: request)
        }

        do {
            try await appState.loginWithCredentials(
                serverURL: "https://mock.vikunja.io/", username: "devuser", password: "devpassword"
            )
            XCTFail("an old server must be refused")
        } catch let NetworkError.serverTooOld(version) {
            XCTAssertEqual(version, VikunjaVersion(major: 2, minor: 3, patch: 0))
        } catch {
            XCTFail("expected .serverTooOld, got \(error)")
        }

        XCTAssertEqual(capturedPaths, [VikunjaAPI.path("/info"), VikunjaAPI.legacyPath("/info")])
        XCTAssertFalse(capturedPaths.contains { $0.hasSuffix("/login") }, "no credentials may be sent")
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertFalse(appState.isLoading)
    }

    @MainActor
    func testTokenLoginRefusesAnOldServerBeforeUsingTheToken() async {
        let appState = loginAppState { request in
            Self.respond(200, #"{"version": "v2.3.9"}"#, to: request)
        }

        do {
            try await appState.login(serverURL: "https://mock.vikunja.io", token: "tk_secret")
            XCTFail("an old server must be refused")
        } catch let NetworkError.serverTooOld(version) {
            XCTAssertEqual(version, VikunjaVersion(major: 2, minor: 3, patch: 9))
        } catch {
            XCTFail("expected .serverTooOld, got \(error)")
        }

        XCTAssertEqual(capturedPaths, [VikunjaAPI.path("/info")])
        XCTAssertTrue(
            MockURLProtocol.capturedRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil },
            "the token must not leave the device"
        )
    }

    /// The server would not say how old it is (a proxy refuses `/info`), but
    /// it has no v2 routes: the validation fetch answering 404 says the same.
    @MainActor
    func testValidationNotFoundWithAnUnknownVersionMeansTooOld() async {
        let appState = loginAppState { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/info") {
                return Self.respond(403, "", to: request)
            }
            return Self.respond(404, #"{"message":"Not Found"}"#, to: request)
        }

        do {
            try await appState.login(serverURL: "https://mock.vikunja.io", token: "tk_secret")
            XCTFail("a server without v2 routes must be refused")
        } catch let NetworkError.serverTooOld(version) {
            XCTAssertNil(version)
        } catch {
            XCTFail("expected .serverTooOld, got \(error)")
        }

        XCTAssertEqual(capturedPaths.last, VikunjaAPI.path("/projects"))
        XCTAssertFalse(appState.isAuthenticated)
    }

    /// A 404 from `/login` is not proof of an old server: one with local
    /// sign-in turned off answers the same way. It stays an ordinary error.
    @MainActor
    func testLoginNotFoundStaysAnOrdinaryServerError() async {
        let appState = loginAppState { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/info") {
                return Self.respond(200, #"{"version": "v2.8.0"}"#, to: request)
            }
            return Self.respond(404, #"{"message":"Not Found"}"#, to: request)
        }

        do {
            try await appState.loginWithCredentials(
                serverURL: "https://mock.vikunja.io", username: "devuser", password: "devpassword"
            )
            XCTFail("the login was refused")
        } catch let NetworkError.serverError(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("expected a plain .serverError, got \(error)")
        }

        XCTAssertEqual(capturedPaths, [VikunjaAPI.path("/info"), VikunjaAPI.path("/login")])
        XCTAssertFalse(appState.isAuthenticated)
    }

    /// An unreadable or unparseable version never blocks sign-in on its own.
    @MainActor
    func testUnknownVersionDoesNotBlockSignIn() async {
        let appState = loginAppState { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/info") {
                return Self.respond(200, #"{"version": "unstable"}"#, to: request)
            }
            if path.hasSuffix("/login") {
                return Self.respond(
                    403,
                    #"{"title":"Forbidden","status":403,"detail":"Wrong username or password.","code":1011}"#,
                    to: request
                )
            }
            return Self.respond(500, "", to: request)
        }

        do {
            try await appState.loginWithCredentials(
                serverURL: "https://mock.vikunja.io", username: "devuser", password: "wrong"
            )
            XCTFail("the password was wrong")
        } catch NetworkError.invalidCredentials {
            // The login request was made, and its own refusal came back.
        } catch {
            XCTFail("expected .invalidCredentials, got \(error)")
        }

        XCTAssertTrue(capturedPaths.contains(VikunjaAPI.path("/login")))
    }
}
