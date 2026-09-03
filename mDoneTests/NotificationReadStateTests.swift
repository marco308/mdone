import XCTest
@testable import mDone

/// Covers #165: notifications came back unread after every app restart because
/// read state was read from a `read` field that Vikunja never sends. The server
/// reports read state through `read_at` alone, using the zero date while unread.
@MainActor
final class NotificationReadStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() async -> APIClient {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return client
    }

    private func respond(with json: String) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    /// The exact shape Vikunja returns: no `read` key at all, and the zero date
    /// for anything still unread.
    private let serverPayload = """
    [
        {
            "id": 1,
            "name": "task.comment",
            "notification": {"doer": {"id": 2, "username": "someone"}},
            "read_at": "2026-08-30T09:15:00Z",
            "created": "2026-08-30T09:00:00Z"
        },
        {
            "id": 2,
            "name": "task.assigned",
            "notification": {"doer": {"id": 2, "username": "someone"}},
            "read_at": "0001-01-01T00:00:00Z",
            "created": "2026-08-31T09:00:00Z"
        }
    ]
    """

    // MARK: - Decoding read state

    func testNotificationReadOnServerDecodesAsRead() async throws {
        respond(with: serverPayload)
        let client = await makeClient()

        let notifications: [VNotification] = try await client.fetch(Endpoint.notifications())

        XCTAssertEqual(notifications.count, 2)
        XCTAssertFalse(notifications[0].isUnread, "read_at holds a real timestamp, so this is read")
    }

    func testNotificationWithZeroReadAtStaysUnread() async throws {
        respond(with: serverPayload)
        let client = await makeClient()

        let notifications: [VNotification] = try await client.fetch(Endpoint.notifications())

        XCTAssertTrue(notifications[1].isUnread, "the zero date means never read")
    }

    func testUnreadCountCountsOnlyServerUnreadNotifications() async throws {
        respond(with: serverPayload)
        let client = await makeClient()
        let notifications: [VNotification] = try await client.fetch(Endpoint.notifications())

        let appState = AppState()
        appState.notifications = notifications

        XCTAssertEqual(appState.unreadNotificationCount, 1, "only the notification with a zero read_at is unread")
    }

    func testMissingReadAtIsTreatedAsUnread() throws {
        // Older servers omit the key entirely rather than sending the zero date.
        let json = """
        {"id": 3, "name": "task.comment", "created": "2026-08-31T09:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let data = try XCTUnwrap(json.data(using: .utf8))
        let notification = try decoder.decode(VNotification.self, from: data)
        XCTAssertTrue(notification.isUnread)
    }

    func testStaleReadFieldDoesNotOverrideReadAt() {
        // `read` is client-side only. A stale true must not mask an unread read_at.
        let notification = VNotification(
            id: 4,
            name: "task.comment",
            notification: nil,
            read: true,
            readAt: Date.distantPast,
            created: nil
        )
        XCTAssertTrue(notification.isUnread)
    }

    // MARK: - Mark-as-read request body

    func testMarkAsReadSendsTheReadFlag() throws {
        // An empty body decodes as read = false on the server, which clears
        // read_at and leaves the notification unread.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data = try encoder.encode(MarkNotificationReadRequest(read: true))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(decoded?["read"] as? Bool, true)
    }
}
