import Foundation
@testable import mDone

/// A custom URLProtocol that intercepts network requests and returns mock responses.
/// Used to test APIClient without making real network calls.
final class MockURLProtocol: URLProtocol {
    /// Guards every piece of static state below.
    ///
    /// The handlers are written from the test thread and read from URLSession's
    /// own protocol threads, so leaving them as bare `static var`s was a data
    /// race: a reader could observe a handler installed by a different test, and
    /// the unsynchronised retain/release could take the whole test host down
    /// mid-run. Only `capturedRequests` used to be locked.
    private static let stateLock = NSLock()

    private static var storedRequestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var storedAsynchronousRequestHandler: ((URLRequest, MockURLProtocol) -> Void)?
    private static var storedCapturedRequests: [URLRequest] = []

    /// Bumped by every `reset()`, and stamped by `mockSession()` onto every
    /// request that session makes.
    ///
    /// APIClient retries transient failures with a 1s/2s/4s backoff, so a
    /// request can still be in flight long after the test that started it
    /// returned. Without this stamp that straggler is handed whichever handler
    /// the *next* test installed, and the next test then fails with an error it
    /// never asked for. Comparing generations turns that into an explicit
    /// failure against the test that leaked the request instead.
    private static var generation: Int = 0
    private static let generationHeader = "X-MockURLProtocol-Generation"

    /// Handler that receives a URLRequest and returns (HTTPURLResponse, Data).
    /// Set this before each test to control the mock response.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { stateLock.withLock { storedRequestHandler } }
        set { stateLock.withLock { storedRequestHandler = newValue } }
    }

    /// Non-blocking variant for tests that need more than one request in flight.
    /// The handler must finish the request through `complete`.
    static var asynchronousRequestHandler: ((URLRequest, MockURLProtocol) -> Void)? {
        get { stateLock.withLock { storedAsynchronousRequestHandler } }
        set { stateLock.withLock { storedAsynchronousRequestHandler = newValue } }
    }

    /// Records all requests made so tests can verify endpoints, headers, etc.
    static var capturedRequests: [URLRequest] {
        stateLock.withLock { storedCapturedRequests }
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestGeneration = request.value(forHTTPHeaderField: MockURLProtocol.generationHeader).flatMap(Int.init)

        // Read the generation and both handlers in one critical section so the
        // request is served by a consistent snapshot of the mock's state.
        let (currentGeneration, syncHandler, asyncHandler) = MockURLProtocol.stateLock.withLock {
            (
                MockURLProtocol.generation,
                MockURLProtocol.storedRequestHandler,
                MockURLProtocol.storedAsynchronousRequestHandler
            )
        }

        // A straggler from a finished test. Fail it rather than letting it run
        // the current test's handler, and keep it out of `capturedRequests`.
        if let requestGeneration, requestGeneration != currentGeneration {
            let error = NSError(domain: "MockURLProtocol", code: -2, userInfo: [
                NSLocalizedDescriptionKey: """
                Request to \(request.url?.absoluteString ?? "<no URL>") arrived from a finished test \
                (generation \(requestGeneration), current \(currentGeneration)). \
                The test that started it returned while the request was still in flight.
                """,
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        MockURLProtocol.capture(request)

        if let asyncHandler {
            asyncHandler(request, self)
            return
        }

        guard let syncHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No request handler set",
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try syncHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Resets all state. Call in setUp/tearDown.
    static func reset() {
        stateLock.withLock {
            storedRequestHandler = nil
            storedAsynchronousRequestHandler = nil
            storedCapturedRequests = []
            generation += 1
        }
    }

    private static func capture(_ request: URLRequest) {
        stateLock.withLock { storedCapturedRequests.append(request) }
    }

    func complete(response: HTTPURLResponse, data: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    // MARK: - Convenience Helpers

    /// Creates an HTTPURLResponse with the given status code for any URL.
    static func makeResponse(statusCode: Int, url: URL? = nil, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://mock.vikunja.io")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    /// Creates a URLSession configured to use this mock protocol.
    ///
    /// The session is stamped with the generation current at the moment it is
    /// built, which is what lets `startLoading` tell this test's requests apart
    /// from a previous test's leftovers. Build the session inside the test, not
    /// in `setUp` before `reset()`.
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [generationHeader: String(stateLock.withLock { generation })]
        return URLSession(configuration: config)
    }

    /// An `APIClient` on the mock session, with the retry backoff collapsed.
    ///
    /// The production 1s/2s/4s backoff means a test exercising a 5xx or an
    /// unreachable server sits for seven real seconds, and leaves the request in
    /// flight for all of them. Retrying immediately keeps the retry paths under
    /// test without the wall clock or the straggling requests.
    static func mockClient() -> APIClient {
        APIClient(session: mockSession(), baseRetryDelay: 0)
    }

    /// Returns a request's body. URLSession hands URLProtocol the body as a
    /// stream (`httpBody` is nil by the time the request reaches the handler),
    /// so tests asserting on request bodies must go through this.
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

extension URLRequest {
    /// The request body decoded as a JSON object, for asserting on payloads.
    var decodedJSONBody: [String: Any]? {
        guard let data = MockURLProtocol.bodyData(from: self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
