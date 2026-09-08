import AuthenticationServices
import XCTest
@testable import mDone

/// `ASWebAuthenticationSession` opens a browser on `start()`, so these tests
/// swap in a session that opens nothing and reports its result from a
/// background queue. That is what the real one does on macOS, where the
/// callback arrives on the browser agent's XPC reply queue rather than the
/// main thread, and it is what crashed every SSO sign-in there (#182).
@MainActor
final class WebAuthenticatorTests: XCTestCase {
    private final class StubSession: WebAuthenticationSession {
        var prefersEphemeralWebBrowserSession = false
        weak var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
        var completion: ASWebAuthenticationSession.CompletionHandler?
        var startReturns = true
        var onStart: () -> Void = {}
        var onCancel: () -> Void = {}
        private(set) var startCount = 0
        private(set) var cancelCount = 0

        func start() -> Bool {
            startCount += 1
            onStart()
            return startReturns
        }

        func cancel() {
            cancelCount += 1
            onCancel()
        }

        /// Reports the result the way AuthenticationServices does on macOS:
        /// on a thread that is not the main one.
        func completeOffMainThread(url: URL?, error: (any Error)?) {
            DispatchQueue.global().async { [completion] in
                XCTAssertFalse(Thread.isMainThread, "the test must exercise the off-main-thread path")
                completion?(url, error)
            }
        }
    }

    private var session = StubSession()
    private var authenticator: WebAuthenticator!
    private var authorizationURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let session = StubSession()
        self.session = session
        authenticator = WebAuthenticator { _, _, completion in
            session.completion = completion
            return session
        }
        authorizationURL = try XCTUnwrap(URL(string: "https://auth.example.com/authorize?state=s"))
    }

    // MARK: - The callback reaching the app

    func testCallbackDeliveredOffTheMainThreadResumesWithTheURL() async throws {
        let expected = try XCTUnwrap(URL(string: "mdone://oidc-callback?code=abc&state=s"))
        session.onStart = { [session] in session.completeOffMainThread(url: expected, error: nil) }

        let url = try await authenticator.authenticate(url: authorizationURL, callbackScheme: "mdone")

        XCTAssertEqual(url, expected)
        XCTAssertEqual(session.startCount, 1)
    }

    func testCancelledLoginDeliveredOffTheMainThreadThrowsCancelled() async {
        session.onStart = { [session] in
            session.completeOffMainThread(url: nil, error: ASWebAuthenticationSessionError(.canceledLogin))
        }

        await assertAuthenticateThrows(.cancelled)
    }

    func testMissingCallbackURLDeliveredOffTheMainThreadThrowsFailed() async {
        session.onStart = { [session] in session.completeOffMainThread(url: nil, error: nil) }

        await assertAuthenticateThrows(.failed("No callback URL"))
    }

    // MARK: - Session setup

    func testConfiguresTheSessionBeforeStarting() async throws {
        var providerAtStart: (any ASWebAuthenticationPresentationContextProviding)?
        var ephemeralAtStart: Bool?
        session.onStart = { [session] in
            providerAtStart = session.presentationContextProvider
            ephemeralAtStart = session.prefersEphemeralWebBrowserSession
            session.completeOffMainThread(url: URL(string: "mdone://oidc-callback"), error: nil)
        }

        _ = try await authenticator.authenticate(
            url: authorizationURL, callbackScheme: "mdone", prefersEphemeralSession: true
        )

        XCTAssertTrue(providerAtStart === authenticator)
        XCTAssertEqual(ephemeralAtStart, true)
    }

    func testStartRefusingThrowsCannotStartWithoutWaitingForACallback() async {
        session.startReturns = false

        await assertAuthenticateThrows(.cannotStart)
        XCTAssertEqual(session.startCount, 1)
    }

    // MARK: - Cancellation

    func testCancelResumesOnceEvenWhenTheSessionAlsoReportsIt() async throws {
        let started = expectation(description: "session started")
        session.onStart = { started.fulfill() }
        // The real session may echo cancel() back through its completion
        // handler. That second report must be swallowed, not resumed again.
        session.onCancel = { [session] in
            session.completeOffMainThread(url: nil, error: ASWebAuthenticationSessionError(.canceledLogin))
        }

        let task = Task { [authenticator, authorizationURL] in
            try await authenticator!.authenticate(url: authorizationURL!, callbackScheme: "mdone")
        }
        await fulfillment(of: [started], timeout: 1)
        authenticator.cancel()

        let result = await task.result
        XCTAssertEqual(session.cancelCount, 1)
        guard case let .failure(error) = result else {
            return XCTFail("expected cancellation, got \(result)")
        }
        XCTAssertEqual(error as? WebAuthenticationError, .cancelled)
        // Let the echoed report land. Resuming twice would trap here.
        try await Task.sleep(for: .milliseconds(100))
    }

    func testTaskCancellationCancelsTheSession() async {
        let started = expectation(description: "session started")
        session.onStart = { started.fulfill() }

        let task = Task { [authenticator, authorizationURL] in
            try await authenticator!.authenticate(url: authorizationURL!, callbackScheme: "mdone")
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        let result = await task.result
        guard case let .failure(error) = result else {
            return XCTFail("expected cancellation, got \(result)")
        }
        XCTAssertEqual(error as? WebAuthenticationError, .cancelled)
        XCTAssertEqual(session.cancelCount, 1)
    }

    // MARK: - Helpers

    private func assertAuthenticateThrows(
        _ expected: WebAuthenticationError, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let url = try await authenticator.authenticate(url: authorizationURL, callbackScheme: "mdone")
            XCTFail("expected \(expected), got \(url)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? WebAuthenticationError, expected, file: file, line: line)
        }
    }
}
