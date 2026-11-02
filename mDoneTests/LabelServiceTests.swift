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
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return LabelService(apiClient: client)
    }

    // MARK: - fetchLabels (issue #139)

    private static func labelsPage(ids: ClosedRange<Int>) -> Data {
        let objects = ids.map { #"{"id": \#($0), "title": "Label \#($0)", "hex_color": "1a8cff"}"# }
        return "[\(objects.joined(separator: ","))]".data(using: .utf8)!
    }

    func testFetchLabelsRequestsLabelsEndpoint() async throws {
        let service = await makeService()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Self.labelsPage(ids: 1 ... 2))
        }

        let labels = try await service.fetchLabels()

        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels.first?.title, "Label 1")
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/labels")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    /// Labels were truncated at one page just like projects, which silently
    /// broke the "Current" label lookup for anyone with a lot of labels.
    func testFetchLabelsFollowsPaginationAcrossPages() async throws {
        let service = await makeService()
        MockURLProtocol.requestHandler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let page = Int(items?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
            let response = MockURLProtocol.makeResponse(
                statusCode: 200,
                url: request.url,
                headers: ["x-pagination-total-pages": "2"]
            )
            return (response, page == 1 ? Self.labelsPage(ids: 1 ... 50) : Self.labelsPage(ids: 51 ... 63))
        }

        let labels = try await service.fetchLabels()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)
        XCTAssertEqual(labels.count, 63)
        XCTAssertTrue(labels.contains { $0.id == 63 }, "labels on the last page must survive")
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
