import XCTest
@testable import mDone

/// Coverage for the JWT-refresh path added for issue #80. The bug was that a
/// stale short-lived JWT caused the app to log the user out on the next
/// request after ~10 minutes. APIClient now:
/// - captures the `vikunja_refresh_token` cookie from `/login` responses
/// - on 401, transparently refreshes the JWT and retries the request once
/// - fires `onSessionExpired` only when refresh isn't possible or itself fails
final class APIClientRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> APIClient {
        APIClient(session: MockURLProtocol.mockSession())
    }

    // MARK: - Cookie capture

    func testLoginCapturesRefreshCookie() async throws {
        let client = makeClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "")

        let loginJSON = #"{"token":"\#(Self.validJWT())"}"#.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(
                statusCode: 200,
                url: request.url,
                headers: ["Set-Cookie": "vikunja_refresh_token=refresh-cookie-abc; Path=/; HttpOnly"]
            )
            return (response, loginJSON)
        }

        let _: LoginResponse = try await client.send(
            Endpoint.login,
            body: LoginRequest(username: "u", password: "p")
        )

        let captured = await client.currentRefreshToken()
        XCTAssertEqual(captured, "refresh-cookie-abc")
    }

    func testNonLoginResponsesWithoutCookieLeaveRefreshTokenUntouched() async throws {
        let client = makeClient()
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: Self.validJWT(),
            refreshToken: "existing-refresh"
        )

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Self.sampleTaskJSON(id: 1))
        }

        let _: VTask = try await client.fetch(Endpoint.task(id: 1))
        let stored = await client.currentRefreshToken()
        XCTAssertEqual(stored, "existing-refresh", "Successful non-auth responses must not clobber the refresh token")
    }

    // MARK: - 401 + refresh + retry

    func testJWT401TriggersRefreshAndRetriesOriginalRequest() async throws {
        let client = makeClient()
        let originalJWT = Self.validJWT()
        let refreshedJWT = Self.validJWT(payloadOverride: ["exp": 9_999_999_999])
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: originalJWT,
            refreshToken: "refresh-1"
        )

        let counter = RequestCounter()

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            counter.record(path: path, authorization: auth, cookie: request.value(forHTTPHeaderField: "Cookie"))

            if path.hasSuffix("/user/token/refresh") {
                let resp = MockURLProtocol.makeResponse(
                    statusCode: 200,
                    url: request.url,
                    headers: ["Set-Cookie": "vikunja_refresh_token=refresh-2; Path=/; HttpOnly"]
                )
                return (resp, #"{"token":"\#(refreshedJWT)"}"#.data(using: .utf8)!)
            }

            // /api/v1/tasks/1: first attempt 401, retry succeeds.
            let attemptForTask = counter.count(forPath: path)
            if attemptForTask == 1 {
                return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                Self.sampleTaskJSON(id: 1)
            )
        }

        let task: VTask = try await client.fetch(Endpoint.task(id: 1))
        XCTAssertEqual(task.id, 1)

        // Three HTTP calls in total: failing fetch → refresh → retried fetch.
        XCTAssertEqual(counter.totalCount, 3)
        let taskCalls = counter.entries(forPath: "/api/v1/tasks/1")
        XCTAssertEqual(taskCalls.count, 2, "Original endpoint should be retried exactly once")
        XCTAssertEqual(taskCalls[0].authorization, "Bearer \(originalJWT)")
        XCTAssertEqual(
            taskCalls[1].authorization,
            "Bearer \(refreshedJWT)",
            "Retry must use the freshly refreshed JWT"
        )

        let refreshCalls = counter.entries(forPath: "/api/v1/user/token/refresh")
        XCTAssertEqual(refreshCalls.count, 1)
        XCTAssertEqual(
            refreshCalls[0].cookie,
            "vikunja_refresh_token=refresh-1",
            "Refresh must send the stored refresh-token cookie"
        )

        // Rotated cookie should have replaced the old refresh token.
        let stored = await client.currentRefreshToken()
        XCTAssertEqual(stored, "refresh-2")
        let storedJWT = await client.currentToken()
        XCTAssertEqual(storedJWT, refreshedJWT)
    }

    func testJWT401WithFailedRefreshFiresSessionExpired() async {
        let client = makeClient()
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: Self.validJWT(),
            refreshToken: "stale-refresh"
        )

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        MockURLProtocol.requestHandler = { request in
            // Refresh endpoint also returns 401 → unrecoverable.
            let resp = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (resp, Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected unauthorized")
        } catch let error as NetworkError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(expiredFlag.value, true)
        // Should also have dropped the refresh token so we don't loop forever.
        let stored = await client.currentRefreshToken()
        XCTAssertNil(stored)
    }

    func testJWT401WithoutRefreshTokenSurfacesUnauthorized() async {
        let client = makeClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: Self.validJWT())

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        var refreshAttempted = false
        MockURLProtocol.requestHandler = { request in
            if (request.url?.path ?? "").contains("/user/token/refresh") {
                refreshAttempted = true
            }
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected unauthorized")
        } catch let error as NetworkError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(refreshAttempted, "Without a refresh cookie, no refresh request should be made")
        XCTAssertEqual(expiredFlag.value, true)
    }

    func testAPITokenSession401DoesNotAttemptRefresh() async {
        let client = makeClient()
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: "tk_apikey_abcdef123456",
            refreshToken: "irrelevant" // shouldn't matter — API token sessions never refresh
        )

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        var refreshAttempted = false
        MockURLProtocol.requestHandler = { request in
            if (request.url?.path ?? "").contains("/user/token/refresh") {
                refreshAttempted = true
            }
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected unauthorized")
        } catch let error as NetworkError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(refreshAttempted, "API-token sessions must never hit the refresh endpoint")
        XCTAssertEqual(expiredFlag.value, true)
    }

    // MARK: - Callback contract

    func testRefreshFiresOnTokensUpdatedCallback() async throws {
        let client = makeClient()
        let originalJWT = Self.validJWT()
        let refreshedJWT = Self.validJWT(payloadOverride: ["exp": 8_888_888_888])
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: originalJWT,
            refreshToken: "refresh-old"
        )

        let captured = AsyncBox<(token: String, refresh: String?)>()
        await client.setOnTokensUpdated { token, refresh in
            captured.set((token: token, refresh: refresh))
        }

        let counter = RequestCounter()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            counter.record(path: path, authorization: "", cookie: nil)
            if path.hasSuffix("/user/token/refresh") {
                return (
                    MockURLProtocol.makeResponse(
                        statusCode: 200,
                        url: request.url,
                        headers: ["Set-Cookie": "vikunja_refresh_token=refresh-new; Path=/; HttpOnly"]
                    ),
                    #"{"token":"\#(refreshedJWT)"}"#.data(using: .utf8)!
                )
            }
            let attempt = counter.count(forPath: path)
            if attempt == 1 {
                return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                Self.sampleTaskJSON(id: 1)
            )
        }

        let _: VTask = try await client.fetch(Endpoint.task(id: 1))

        let result = captured.value
        XCTAssertEqual(result?.token, refreshedJWT)
        XCTAssertEqual(result?.refresh, "refresh-new")
    }

    // MARK: - Edge cases surfaced by PR review

    /// Real `HTTPURLResponse.allHeaderFields` is `[AnyHashable: Any]` whose
    /// values may be `NSString`. Cookie capture must still work in that case.
    func testStringHeadersNormalisesMixedKeyValueTypes() {
        let raw: [AnyHashable: Any] = [
            "Set-Cookie": "vikunja_refresh_token=value1; Path=/",
            "X-Foo" as NSString: "swift-string-value",
            "X-Bar": "nsstring-value" as NSString,
            // NSString key + NSString value — the previous `as? [String: String]`
            // cast in `captureRefreshCookie` would silently drop this one even
            // though Foundation can deliver it from a real response.
            "X-Baz" as NSString: "both-ns" as NSString,
            // Non-string values should be skipped rather than crashing.
            "X-Ignored": 42,
        ]

        let normalised = APIClient.stringHeaders(from: raw)
        XCTAssertEqual(normalised["Set-Cookie"], "vikunja_refresh_token=value1; Path=/")
        XCTAssertEqual(normalised["X-Foo"], "swift-string-value")
        XCTAssertEqual(normalised["X-Bar"], "nsstring-value")
        XCTAssertEqual(normalised["X-Baz"], "both-ns")
        XCTAssertNil(normalised["X-Ignored"])
    }

    /// Transport failure during refresh (offline, timeout, DNS) must not be
    /// mistaken for an auth failure. Previously this called `expireSession()`
    /// and bounced users to the login screen over a momentary network blip.
    func testTransportErrorDuringRefreshDoesNotExpireSession() async {
        let client = makeClient()
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: Self.validJWT(),
            refreshToken: "refresh-token-1"
        )

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/user/token/refresh") {
                // Simulate offline mid-refresh.
                throw URLError(.notConnectedToInternet)
            }
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected the transport error to propagate")
        } catch let error as NetworkError {
            // Either .networkUnavailable or .unknown — what matters is that
            // we did NOT silently swallow the failure as .unauthorized.
            if case .unauthorized = error {
                XCTFail("Transport error during refresh must not surface as .unauthorized")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertNotEqual(
            expiredFlag.value,
            true,
            "Session must survive a transient refresh failure"
        )
        let stillStored = await client.currentRefreshToken()
        XCTAssertEqual(
            stillStored,
            "refresh-token-1",
            "Refresh token must not be dropped on transport error so the next attempt can succeed"
        )
    }

    /// A 5xx from the refresh endpoint is transient — let the caller retry the
    /// original request later rather than killing the session.
    func testServerErrorDuringRefreshDoesNotExpireSession() async {
        let client = makeClient()
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: Self.validJWT(),
            refreshToken: "refresh-token-1"
        )

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/user/token/refresh") {
                return (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
            }
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected server error to propagate")
        } catch let error as NetworkError {
            if case .unauthorized = error {
                XCTFail("5xx during refresh must not surface as .unauthorized")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertNotEqual(expiredFlag.value, true)
    }

    /// If the retried request also returns 401 (server raced the rotation, or
    /// the freshly-issued JWT is somehow already invalid), we still need to
    /// notify session-expired so AppState can surface the login screen instead
    /// of leaving the user stuck on a broken-but-not-flagged session.
    func testRetriedRequestAlso401FiresSessionExpired() async {
        let client = makeClient()
        let originalJWT = Self.validJWT()
        let refreshedJWT = Self.validJWT(payloadOverride: ["exp": 9_000_000_000])
        await client.configure(
            serverURL: "https://mock.vikunja.io",
            token: originalJWT,
            refreshToken: "refresh-1"
        )

        let expiredFlag = AsyncBox<Bool>()
        await client.setOnSessionExpired { expiredFlag.set(true) }

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/user/token/refresh") {
                let resp = MockURLProtocol.makeResponse(
                    statusCode: 200,
                    url: request.url,
                    headers: ["Set-Cookie": "vikunja_refresh_token=refresh-2; Path=/"]
                )
                return (resp, #"{"token":"\#(refreshedJWT)"}"#.data(using: .utf8)!)
            }
            // Every call to the original endpoint 401s, even after refresh.
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected unauthorized")
        } catch let error as NetworkError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(
            expiredFlag.value,
            true,
            "Persistent 401 after a successful refresh must escalate to session expiry"
        )
    }

    // MARK: - Helpers

    /// Builds a JWT-shaped token. We never verify signatures — only the
    /// three-segments + base64-decodable-payload shape matters to APIClient.
    private static func validJWT(payloadOverride: [String: Any] = [:]) -> String {
        let header = base64URL(Data(#"{"alg":"HS256"}"#.utf8))
        var payload: [String: Any] = ["sub": "1", "exp": 1_700_000_000]
        for (k, v) in payloadOverride {
            payload[k] = v
        }
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let body = base64URL(payloadData)
        let sig = base64URL(Data("sig".utf8))
        return "\(header).\(body).\(sig)"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sampleTaskJSON(id: Int) -> Data {
        #"""
        {
            "id": \#(id),
            "title": "Task \#(id)",
            "done": false,
            "priority": 0,
            "project_id": 1,
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """#.data(using: .utf8)!
    }
}

// MARK: - Test-local concurrency helpers

/// Thread-safe value collector used to capture closure callbacks fired from
/// actor methods or background mocks.
private final class AsyncBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
    }
}

/// Records the requests that hit MockURLProtocol so refresh-flow tests can
/// assert on the sequence (path → which attempt → which Authorization/Cookie).
private final class RequestCounter: @unchecked Sendable {
    struct Entry {
        let authorization: String
        let cookie: String?
    }

    private let lock = NSLock()
    private var perPath: [String: [Entry]] = [:]
    private var total = 0

    var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    func record(path: String, authorization: String, cookie: String?) {
        lock.lock()
        defer { lock.unlock() }
        perPath[path, default: []].append(Entry(authorization: authorization, cookie: cookie))
        total += 1
    }

    func count(forPath path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return perPath[path]?.count ?? 0
    }

    func entries(forPath path: String) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return perPath[path] ?? []
    }
}
