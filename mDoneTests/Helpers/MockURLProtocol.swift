import Foundation

/// A custom URLProtocol that intercepts network requests and returns mock responses.
/// Used to test APIClient without making real network calls.
final class MockURLProtocol: URLProtocol {
    /// Handler that receives a URLRequest and returns (HTTPURLResponse, Data).
    /// Set this before each test to control the mock response.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Records all requests made so tests can verify endpoints, headers, etc.
    static var capturedRequests: [URLRequest] = []

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

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
        capturedRequests = []
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
}
