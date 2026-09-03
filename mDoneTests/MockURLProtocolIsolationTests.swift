import XCTest
@testable import mDone

/// Covers the isolation guarantees the rest of the suite leans on.
///
/// `MockURLProtocol` holds its handler in static state shared by every test in
/// the bundle, and APIClient retries transient failures, so a request can still
/// be in flight after the test that started it has returned. Without these
/// guarantees that straggler runs the *next* test's handler and fails it with an
/// error it never set up, which is why a different test used to fail on each
/// full-suite run.
final class MockURLProtocolIsolationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRequestFromABeforeResetSessionIsRejected() async throws {
        // A session built by a "previous test", which then finished.
        let staleSession = MockURLProtocol.mockSession()
        MockURLProtocol.reset()

        // The "next test" installs its own handler.
        let served = expectation(description: "handler ran")
        served.isInverted = true
        MockURLProtocol.requestHandler = { request in
            served.fulfill()
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        do {
            _ = try await staleSession.data(from: XCTUnwrap(URL(string: "https://mock.vikunja.io/api/v1/tasks")))
            XCTFail("A request from a finished test must not be served")
        } catch {
            XCTAssertEqual((error as NSError).domain, "MockURLProtocol")
        }

        await fulfillment(of: [served], timeout: 0.5)
        XCTAssertTrue(
            MockURLProtocol.capturedRequests.isEmpty,
            "A rejected straggler must not land in the current test's captured requests"
        )
    }

    func testRequestFromTheCurrentSessionIsServed() async throws {
        let session = MockURLProtocol.mockSession()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data("{}".utf8))
        }

        let url = try XCTUnwrap(URL(string: "https://mock.vikunja.io/api/v1/tasks"))
        let (data, response) = try await session.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, Data("{}".utf8))
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    /// The retry paths have to stay exercised, just without the wall clock.
    func testMockClientStillRetriesTransientFailuresWithoutTheBackoff() async throws {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }

        let started = Date()
        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected the unreachable server to surface as an error")
        } catch {
            // Expected.
        }

        // 1 initial attempt + 3 retries, and none of the 1s/2s/4s backoff.
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 4)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }
}
