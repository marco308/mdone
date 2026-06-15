import XCTest
@testable import mDone

final class LabelServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeService() async -> LabelService {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return LabelService(apiClient: client)
    }

    func testCreateLabelPutsToLabelsAndDecodes() async throws {
        let service = await makeService()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 7, "title": "Current", "hex_color": "1a8cff"}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), json)
        }

        let label = try await service.createLabel(LabelCreateRequest(title: "Current", hexColor: "1a8cff"))

        XCTAssertEqual(label.id, 7)
        XCTAssertEqual(label.title, "Current")
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/labels")
        XCTAssertEqual(request.httpMethod, "PUT")
    }

    func testAddLabelPutsToTaskLabelsEndpoint() async throws {
        let service = await makeService()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"label_id": 7}"#.data(using: .utf8)!)
        }

        try await service.addLabel(taskId: 42, labelId: 7)

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/tasks/42/labels")
        XCTAssertEqual(request.httpMethod, "PUT")
    }

    func testRemoveLabelDeletesFromTaskLabelEndpoint() async throws {
        let service = await makeService()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"message": "ok"}"#.data(using: .utf8)!)
        }

        try await service.removeLabel(taskId: 42, labelId: 7)

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/tasks/42/labels/7")
        XCTAssertEqual(request.httpMethod, "DELETE")
    }
}
