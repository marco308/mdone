#if os(iOS)
import SwiftData
import XCTest
@testable import mDone

/// Tests for the focus-service outbox (mdone#62). Network is mocked via
/// `MockURLProtocol`, SwiftData lives in-memory. FocusSyncConfig is touched
/// through the real Keychain/UserDefaults — setUp/tearDown clean it.
@MainActor
final class FocusOutboxServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var outbox: FocusOutboxService!
    private let testURL = "https://focus.test.invalid"
    private let testToken = "test-token"

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()

        let schema = Schema([FocusRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])

        FocusSyncConfig.saveServerURL(testURL)
        FocusSyncConfig.saveToken(testToken)

        outbox = FocusOutboxService(modelContainer: container, session: MockURLProtocol.mockSession())
    }

    override func tearDown() async throws {
        FocusSyncConfig.clearServerURL()
        FocusSyncConfig.deleteToken()
        MockURLProtocol.reset()
        container = nil
        outbox = nil
        try await super.tearDown()
    }

    // MARK: - Happy path

    func testDrainPostsAndMarksDelivered() async throws {
        let record = insertRecord(taskId: 1)
        MockURLProtocol.requestHandler = { _ in
            let body = Data(#"{"id":1,"received_at":"2026-05-16T10:00:00Z","duplicate":false}"#.utf8)
            return (MockURLProtocol.makeResponse(statusCode: 201), body)
        }

        await outbox.drain()

        XCTAssertNotNil(record.deliveredAt, "Record should be marked delivered after 201")
        XCTAssertNotNil(record.clientId, "Drain must lazily fill clientId for records without one")
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    func testDrainSendsBearerToken() async throws {
        _ = insertRecord(taskId: 2)
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(testToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testPayloadIsSnakeCaseWithRequiredFields() async throws {
        _ = insertRecord(taskId: 7, taskTitle: "Write report", projectName: "Work", focused: 600)
        var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            capturedBody = request.bodyStreamData() ?? request.httpBody
            return (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        let body = try XCTUnwrap(capturedBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["task_id"] as? Int, 7)
        XCTAssertEqual(json["task_title"] as? String, "Write report")
        XCTAssertEqual(json["project_name"] as? String, "Work")
        XCTAssertEqual(json["focused_seconds"] as? Double, 600)
        XCTAssertNotNil(json["client_id"])
        XCTAssertNotNil(json["started_at"])
        XCTAssertNotNil(json["ended_at"])
    }

    // MARK: - Backfill of pre-outbox records

    func testBackfillsExistingRecordsWithoutClientId() async throws {
        let r1 = insertRecord(taskId: 10, clientId: nil)
        let r2 = insertRecord(taskId: 11, clientId: nil)
        let r3 = insertRecord(taskId: 12, clientId: nil)

        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 3)
        for record in [r1, r2, r3] {
            XCTAssertNotNil(record.clientId, "All pre-outbox records should get clientId assigned")
            XCTAssertNotNil(record.deliveredAt)
        }
    }

    func testAlreadyDeliveredRecordsNotResent() async throws {
        _ = insertRecord(taskId: 20, deliveredAt: Date())
        _ = insertRecord(taskId: 21, deliveredAt: nil)

        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1, "Only the pending record should be POSTed")
    }

    // MARK: - Error handling

    func testRateLimitedHaltsDrain() async throws {
        _ = insertRecord(taskId: 30)
        _ = insertRecord(taskId: 31)
        var calls = 0
        MockURLProtocol.requestHandler = { _ in
            calls += 1
            let headers = ["Retry-After": "60"]
            return (MockURLProtocol.makeResponse(statusCode: 429, headers: headers), Data("{}".utf8))
        }

        await outbox.drain()

        XCTAssertEqual(calls, 1, "Drain must stop after a 429, not hammer the server")
    }

    func testRateLimitedSubsequentDrainSkipsUntilCooldown() async throws {
        _ = insertRecord(taskId: 40)
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 429, headers: ["Retry-After": "60"]), Data())
        }

        await outbox.drain()
        let firstCallCount = MockURLProtocol.capturedRequests.count

        // Immediate retry must be short-circuited by the cooldown.
        await outbox.drain()
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, firstCallCount)
    }

    func testAuthFailureStopsDrainWithoutMarkingDelivered() async throws {
        let record = insertRecord(taskId: 50)
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 401), Data())
        }

        await outbox.drain()

        XCTAssertNil(record.deliveredAt, "401 must not mark the record delivered — user needs to fix token")
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    func testSchemaRejectionDiscardsRecordAndContinues() async throws {
        let bad = insertRecord(taskId: 60)
        let good = insertRecord(taskId: 61)
        var seenTaskIds: [Int] = []
        MockURLProtocol.requestHandler = { request in
            let body = request.bodyStreamData() ?? request.httpBody ?? Data()
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let taskId = json["task_id"] as? Int
            {
                seenTaskIds.append(taskId)
                if taskId == 60 {
                    return (MockURLProtocol.makeResponse(statusCode: 422), Data(#"{"detail":"bad"}"#.utf8))
                }
            }
            return (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        XCTAssertEqual(seenTaskIds, [60, 61], "Drain must continue past a 422 to the next record")
        XCTAssertNil(bad.deliveredAt)
        XCTAssertNotNil(bad.discardedAt, "422 must mark the record discarded so it isn't retried forever")
        XCTAssertNotNil(good.deliveredAt)
    }

    func testDiscardedRecordsNotRetriedOnSubsequentDrain() async throws {
        // First drain: get a 422, record gets discarded.
        let record = insertRecord(taskId: 65)
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 422), Data(#"{"detail":"bad"}"#.utf8))
        }
        await outbox.drain()
        XCTAssertNotNil(record.discardedAt)
        let firstCallCount = MockURLProtocol.capturedRequests.count

        // Second drain: server is now healthy. The discarded record should
        // NOT be retried (the schema problem requires a code fix, not a retry).
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }
        await outbox.drain()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, firstCallCount, "Discarded records must not be retried")
    }

    // MARK: - Multi-batch drain

    func testDrainLoopsAcrossMultipleBatches() async throws {
        // Insert more than one batch worth of records (51 > batchSize 50).
        // A single-batch implementation would only deliver the first 50.
        let total = 55
        for index in 0 ..< total {
            insertRecord(taskId: Int64(1000 + index))
        }
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 201), Data("{}".utf8))
        }

        await outbox.drain()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, total, "Drain must continue across batches until pending is empty")
    }

    func testTransientServerErrorStopsButLeavesRecordPending() async throws {
        let record = insertRecord(taskId: 70)
        MockURLProtocol.requestHandler = { _ in
            (MockURLProtocol.makeResponse(statusCode: 502), Data())
        }

        await outbox.drain()

        XCTAssertNil(record.deliveredAt, "5xx must not mark delivered — retry on next drain")
    }

    // MARK: - Unconfigured / no-op

    func testUnconfiguredDrainIsNoOp() async throws {
        FocusSyncConfig.clearServerURL()
        FocusSyncConfig.deleteToken()
        _ = insertRecord(taskId: 80)

        await outbox.drain()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 0)
    }

    // MARK: - Helpers

    @discardableResult
    private func insertRecord(
        taskId: Int64,
        taskTitle: String = "T",
        projectName: String = "P",
        focused: Double = 60,
        clientId: String? = nil,
        deliveredAt: Date? = nil
    ) -> FocusRecord {
        let record = FocusRecord(
            taskId: taskId,
            taskTitle: taskTitle,
            projectName: projectName,
            priorityLevel: 0,
            startedAt: Date(timeIntervalSinceReferenceDate: Double(taskId) * 60),
            endedAt: Date(timeIntervalSinceReferenceDate: Double(taskId) * 60 + focused),
            focusedSeconds: focused,
            device: "hash",
            clientId: clientId,
            deliveredAt: deliveredAt
        )
        container.mainContext.insert(record)
        try? container.mainContext.save()
        return record
    }
}

private extension URLRequest {
    /// MockURLProtocol delivers the body as a stream — read it once into Data.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

// MARK: - FocusSyncConfig direct unit tests

final class FocusSyncConfigTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FocusSyncConfig.clearServerURL()
        FocusSyncConfig.deleteToken()
    }

    override func tearDown() {
        FocusSyncConfig.clearServerURL()
        FocusSyncConfig.deleteToken()
        super.tearDown()
    }

    func testSaveAndGetServerURL() {
        FocusSyncConfig.saveServerURL("https://focus.example.com")
        XCTAssertEqual(FocusSyncConfig.getServerURL(), "https://focus.example.com")
    }

    func testEmptyURLClears() {
        FocusSyncConfig.saveServerURL("https://focus.example.com")
        FocusSyncConfig.saveServerURL("")
        XCTAssertNil(FocusSyncConfig.getServerURL())
    }

    func testWhitespaceURLTreatedAsEmpty() {
        FocusSyncConfig.saveServerURL("   \n\t  ")
        XCTAssertNil(FocusSyncConfig.getServerURL())
    }

    func testFocusEventsURLAppendsPath() {
        FocusSyncConfig.saveServerURL("https://focus.example.com")
        XCTAssertEqual(
            FocusSyncConfig.focusEventsURL()?.absoluteString,
            "https://focus.example.com/focus-events"
        )
    }

    func testFocusEventsURLNilWhenUnconfigured() {
        XCTAssertNil(FocusSyncConfig.focusEventsURL())
    }

    func testIsConfiguredRequiresBoth() {
        XCTAssertFalse(FocusSyncConfig.isConfigured())
        FocusSyncConfig.saveServerURL("https://focus.example.com")
        XCTAssertFalse(FocusSyncConfig.isConfigured(), "URL alone shouldn't count as configured")
        FocusSyncConfig.saveToken("t")
        XCTAssertTrue(FocusSyncConfig.isConfigured())
    }

    func testBareHostnameRejectedAsNotConfigured() {
        // URL(string: "focus.example.com") returns non-nil but has no scheme,
        // so URLSession can't deliver. Settings UI must show "not configured"
        // rather than letting the user think sync is on.
        FocusSyncConfig.saveServerURL("focus.example.com")
        FocusSyncConfig.saveToken("t")
        XCTAssertNil(FocusSyncConfig.focusEventsURL())
        XCTAssertFalse(FocusSyncConfig.isConfigured())
    }

    func testNonHttpSchemeRejected() {
        FocusSyncConfig.saveServerURL("ftp://focus.example.com")
        FocusSyncConfig.saveToken("t")
        XCTAssertNil(FocusSyncConfig.focusEventsURL())
        XCTAssertFalse(FocusSyncConfig.isConfigured())
    }

    func testHttpsSchemeAccepted() {
        FocusSyncConfig.saveServerURL("https://focus.example.com")
        XCTAssertEqual(FocusSyncConfig.focusEventsURL()?.absoluteString, "https://focus.example.com/focus-events")
    }

    func testHttpSchemeAccepted() {
        // Useful for the local dev compose on the LAN.
        FocusSyncConfig.saveServerURL("http://localhost:8090")
        XCTAssertEqual(FocusSyncConfig.focusEventsURL()?.absoluteString, "http://localhost:8090/focus-events")
    }

    func testTokenRoundTrips() {
        FocusSyncConfig.saveToken("supersecret")
        XCTAssertEqual(FocusSyncConfig.getToken(), "supersecret")
    }

    func testEmptyTokenClears() {
        FocusSyncConfig.saveToken("a")
        FocusSyncConfig.saveToken("")
        XCTAssertNil(FocusSyncConfig.getToken())
    }
}
#endif
