import Foundation

/// A custom URLProtocol that intercepts network requests and returns mock responses.
/// Used to test APIClient without making real network calls.
final class MockURLProtocol: URLProtocol {
    /// Handler that receives a URLRequest and returns (HTTPURLResponse, Data).
    /// Set this before each test to control the mock response.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Non-blocking variant for tests that need more than one request in flight.
    /// The handler must finish the request through `complete`.
    static var asynchronousRequestHandler: ((URLRequest, MockURLProtocol) -> Void)?

    /// Records all requests made so tests can verify endpoints, headers, etc.
    private static let capturedRequestsLock = NSLock()
    private static var storedCapturedRequests: [URLRequest] = []
    static var capturedRequests: [URLRequest] {
        capturedRequestsLock.lock()
        defer { capturedRequestsLock.unlock() }
        return storedCapturedRequests
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
        MockURLProtocol.capture(request)

        if let handler = MockURLProtocol.asynchronousRequestHandler {
            handler(request, self)
            return
        }

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No request handler set",
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
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
        requestHandler = nil
        asynchronousRequestHandler = nil
        capturedRequestsLock.lock()
        storedCapturedRequests = []
        capturedRequestsLock.unlock()
    }

    private static func capture(_ request: URLRequest) {
        capturedRequestsLock.lock()
        defer { capturedRequestsLock.unlock() }
        storedCapturedRequests.append(request)
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
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Returns a request's body. URLSession hands URLProtocol the body as a
    /// stream (`httpBody` is nil by the time the request reaches the handler),
    /// so tests asserting on request bodies must go through this.
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
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
