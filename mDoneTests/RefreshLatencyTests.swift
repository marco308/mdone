import XCTest
@testable import mDone

/// A refresh against a slow server: pages, labels and the projects opened
/// this session are read side by side instead of one round trip after
/// another (#276).
@MainActor
final class RefreshLatencyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private nonisolated static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }

    private nonisolated static func tasksJSON(_ ids: [Int64]) -> Data {
        json(ids.map { ["id": $0, "title": "Task \($0)", "done": false, "priority": 0, "project_id": 1] })
    }

    private nonisolated static func page(of request: URLRequest) -> Int {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        return Int(items?.first { $0.name == "page" }?.value ?? "1") ?? 1
    }

    /// Counts requests and the most in flight at once, answering each after
    /// `latency` (or the per-page `delay`).
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests = 0
        private(set) var maxInFlight = 0
        private var inFlight = 0

        func begin() {
            lock.withLock {
                requests += 1
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
            }
        }

        func end() {
            lock.withLock { inFlight -= 1 }
        }
    }

    func testFetchAllPagesKeepsPageOrderWhenPagesArriveOutOfOrder() async throws {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let server = Server()
        MockURLProtocol.asynchronousRequestHandler = { request, proto in
            server.begin()
            let page = Self.page(of: request)
            let response = MockURLProtocol.makeResponse(
                statusCode: 200, url: request.url, headers: ["x-pagination-total-pages": "9"]
            )
            // Later pages answer first.
            let delay = page == 1 ? 0 : Double(10 - page) * 0.01
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                server.end()
                proto.complete(response: response, data: Self.tasksJSON([Int64(page * 10), Int64(page * 10 + 1)]))
            }
        }

        let tasks: [VTask] = try await client.fetchAllPages({ page, perPage in
            Endpoint.allTasks(page: page, perPage: perPage)
        }, perPage: 2)

        var expected: [Int64] = []
        for page: Int64 in 1 ... 9 {
            expected += [page * 10, page * 10 + 1]
        }
        XCTAssertEqual(tasks.map(\.id), expected)
        XCTAssertEqual(server.requests, 9)
        XCTAssertEqual(server.maxInFlight, APIClient.maxConcurrentPages)
    }

    func testFetchAllPagesFailsWhenAPageFails() async {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        MockURLProtocol.requestHandler = { request in
            let status = Self.page(of: request) == 3 ? 404 : 200
            let response = MockURLProtocol.makeResponse(
                statusCode: status, url: request.url, headers: ["x-pagination-total-pages": "5"]
            )
            return (response, Self.tasksJSON([1]))
        }

        do {
            let _: [VTask] = try await client.fetchAllPages({ page, perPage in
                Endpoint.allTasks(page: page, perPage: perPage)
            }, perPage: 1)
            XCTFail("expected the failed page to fail the fetch")
        } catch {}
    }

    /// 600 open tasks (12 pages, as Vikunja caps a page at 50) and six
    /// projects opened this session, each two pages, with 150 ms per request.
    /// One after another that is 26 round trips, about 4 s; side by side it
    /// is a handful.
    func testRefreshAllOverlapsItsRequests() async {
        let latency: TimeInterval = 0.15
        let projectIds: [Int64] = [1, 2, 3, 4, 5, 6]
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
        for id in projectIds {
            state.projectTaskCache[id] = []
        }
        let projectsJSON = Self.json(projectIds.map {
            [
                "id": $0,
                "title": "P\($0)",
                "views": [["id": $0 * 10, "title": "List", "project_id": $0, "view_kind": "list"]],
            ]
        })
        let server = Server()
        MockURLProtocol.asynchronousRequestHandler = { request, proto in
            server.begin()
            let path = request.url!.path
            let page = Self.page(of: request)
            var body = Self.json([])
            var pages = 1
            if path == "/api/v1/tasks" {
                pages = 12
                let start = Int64((page - 1) * 50)
                body = Self.tasksJSON(Array(start + 1 ... start + 50))
            } else if path.hasSuffix("/projects") {
                body = projectsJSON
            } else if path.contains("/views/") {
                pages = 2
                body = Self.tasksJSON([Int64(page)])
            }
            let response = MockURLProtocol.makeResponse(
                statusCode: 200, url: request.url, headers: ["x-pagination-total-pages": "\(pages)"]
            )
            DispatchQueue.global().asyncAfter(deadline: .now() + latency) {
                server.end()
                proto.complete(response: response, data: body)
            }
        }

        let start = Date()
        await state.refreshAll()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(state.tasks.count, 600)
        XCTAssertEqual(state.projectTaskCache.count, projectIds.count)
        XCTAssertEqual(server.requests, 26)
        XCTAssertGreaterThan(server.maxInFlight, 2)
        XCTAssertLessThan(elapsed, Double(server.requests) * latency * 0.5)
    }
}
