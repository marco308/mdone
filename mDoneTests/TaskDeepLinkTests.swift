import XCTest
@testable import mDone

final class TaskDeepLinkTests: XCTestCase {
    func link(_ id: String = "42", server: String = "https://tasks.example.com/vikunja/") -> URL {
        var parts = URLComponents(string: "\(TaskDeepLink.scheme)://task/\(id)")!
        parts.queryItems = [.init(name: "server", value: server)]
        return parts.url!
    }

    func testServerAndTaskIdentityIncludesBasePath() throws {
        let value = try TaskDeepLink(url: link())
        XCTAssertEqual(value.taskID, 42)
        XCTAssertTrue(value.matches(serverURL: "https://TASKS.example.com:443/vikunja"))
        for wrong in [
            "https://tasks.example.com",
            "https://tasks.example.com/other",
            "http://tasks.example.com/vikunja",
            "https://other.example.com/vikunja",
            "https://tasks.example.com:8443/vikunja",
        ] {
            XCTAssertFalse(value.matches(serverURL: wrong), wrong)
        }
    }

    func testMalformedIDsAndUnexpectedFieldsAreRejected() throws {
        for id in ["0", "-1", "+1", "01", "1.2", "42/", "42/7", "9223372036854775808", "abc"] {
            XCTAssertThrowsError(try TaskDeepLink(url: link(id)), id)
        }
        for raw in [
            "\(TaskDeepLink.scheme)://task/42",
            "\(TaskDeepLink.scheme)://task/42?server=https://tasks.example.com&server=https://other.example.com",
            "\(TaskDeepLink.scheme)://task/42?server=https://tasks.example.com&token=secret",
            "\(TaskDeepLink.scheme)://task/42?server=https://tasks.example.com#x",
            "\(TaskDeepLink.scheme)://user@task/42?server=https://tasks.example.com",
            "\(TaskDeepLink.scheme)://task:80/42?server=https://tasks.example.com",
            "\(TaskDeepLink.scheme)://task/%34%32?server=https://tasks.example.com",
        ] {
            XCTAssertThrowsError(try TaskDeepLink(url: XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testUntrustedOrAmbiguousServerURLsAreRejected() {
        for server in [
            "tasks.example.com",
            "file:///tmp/task",
            "https://user:secret@tasks.example.com",
            "https://tasks.example.com?token=x",
            "https://tasks.example.com#x",
            "https://tasks.example.com/a/../b",
            "https://tasks.example.com/a/%2E%2E",
            "https://tasks.example.com/a%2Fb",
            "https://tasks.example.com/a%5Cb",
            "https://tasks.example.com/a//b",
            "https://tasks.example.com:0",
        ] {
            XCTAssertThrowsError(try TaskDeepLink(url: link(server: server)), server)
        }
    }

    func testLocalDevelopmentAndEncodedBasePath() throws {
        XCTAssertTrue(try TaskDeepLink(url: link(server: "http://localhost:3456"))
            .matches(serverURL: "http://localhost:3456/"))
        XCTAssertTrue(try TaskDeepLink(url: link(server: "https://tasks.example.com/%76ikunja"))
            .matches(serverURL: "https://tasks.example.com/vikunja/"))
    }

    func testForkSchemeIsExplicitAndDoesNotAcceptStockLinks() throws {
        let url = try XCTUnwrap(URL(string: "mdone-preview://task/42?server=https://tasks.example.com"))
        XCTAssertEqual(try TaskDeepLink(url: url, scheme: "mdone-preview").taskID, 42)
        XCTAssertThrowsError(try TaskDeepLink(url: url, scheme: "mdone"))
        XCTAssertThrowsError(try TaskDeepLink(
            url: XCTUnwrap(URL(string: "mdone://task/42?server=https://tasks.example.com")),
            scheme: "mdone-preview"
        ))
    }
}

@MainActor
final class TaskLinkRouterTests: XCTestCase {
    let server = "https://tasks.example.com"
    var url: URL {
        URL(string: "\(TaskDeepLink.scheme)://task/42?server=https://tasks.example.com")!
    }

    var task: VTask {
        VTask(id: 42, title: "Synthetic linked task", done: false, priority: 0, projectId: 1)
    }

    func testColdLinkWaitsForSignInThenResolves() async {
        let router = TaskLinkRouter()
        XCTAssertTrue(router.receive(url))
        await router.resolve(authenticated: false, serverURL: nil) { _ in
            XCTFail("No network before sign-in")
            return self.task
        }
        XCTAssertNotNil(router.request)
        XCTAssertNil(router.task)
        await router.resolve(authenticated: true, serverURL: server) { link in
            XCTAssertEqual(link.taskID, 42)
            return self.task
        }
        XCTAssertEqual(router.task?.id, 42)
        XCTAssertNil(router.message)
    }

    func testWrongServerNeverFetchesAndKeepsConnectionChoice() async {
        let router = TaskLinkRouter()
        router.receive(url)
        await router.resolve(authenticated: true, serverURL: "https://other.example.com") { _ in
            XCTFail("Wrong server must not receive a request")
            return self.task
        }
        XCTAssertNil(router.task)
        XCTAssertEqual(router.message, TaskLinkFailure.wrongServer.localizedDescription)
    }

    func testOfflineAndUnavailableErrorsStayVisibleAndCanRetry() async {
        for error in [TaskLinkFailure.offline, .unavailable] {
            let router = TaskLinkRouter()
            router.receive(url)
            await router.resolve(authenticated: true, serverURL: server) { _ in throw error }
            XCTAssertEqual(router.message, error.localizedDescription)
            XCTAssertFalse(router.isLoading)
            XCTAssertTrue(router.isPresented)
            router.retry()
            await router.resolve(authenticated: true, serverURL: server) { _ in self.task }
            XCTAssertEqual(router.task?.id, 42)
        }
    }

    func testNewDestinationDiscardsLateRead() async {
        let router = TaskLinkRouter()
        router.receive(url)
        await router.resolve(authenticated: true, serverURL: server) { _ in
            router.receive(URL(string: "\(TaskDeepLink.scheme)://task/43?server=https://tasks.example.com")!)
            return self.task
        }
        XCTAssertNil(router.task)
        XCTAssertEqual(router.request?.taskID, 43)
    }

    func testDismissDiscardsLateRead() async {
        let router = TaskLinkRouter()
        router.receive(url)
        await router.resolve(authenticated: true, serverURL: server) { _ in
            router.dismiss()
            return self.task
        }
        XCTAssertFalse(router.isPresented)
        XCTAssertNil(router.task)
    }

    func testExistingAndUnsupportedRoutesAreLeftToTheirHandlers() throws {
        let router = TaskLinkRouter()
        for value in [
            "\(TaskDeepLink.scheme)://create",
            "\(TaskDeepLink.scheme)://focus",
            "\(TaskDeepLink.scheme)://project/1",
            "https://tasks.example.com/tasks/42",
        ] {
            XCTAssertFalse(try router.receive(XCTUnwrap(URL(string: value))))
            XCTAssertFalse(router.isPresented)
        }
        XCTAssertTrue(try router.receive(XCTUnwrap(URL(string: "\(TaskDeepLink.scheme)://task/nope"))))
        XCTAssertNotNil(router.message)
    }
}

@MainActor
final class LinkedTaskReadTests: XCTestCase {
    var oldServer: String?
    override func setUp() {
        super.setUp()
        oldServer = AuthService.shared.getServerURL()
        AuthService.shared.saveServerURL("https://mock.vikunja.io/base")
        MockURLProtocol.reset()
    }

    override func tearDown() {
        if let oldServer {
            AuthService.shared.saveServerURL(oldServer)
        } else {
            AuthService.shared.clearServerURL()
        }
        MockURLProtocol.reset()
        super.tearDown()
    }

    func app() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io/base", token: "test-token")
        let state = AppState(taskService: TaskService(apiClient: client))
        state.isAuthenticated = true
        return state
    }

    func testCachedAndUncachedTaskReadsUseConfiguredClientWithoutWrites() async throws {
        let link =
            try TaskDeepLink(
                url: XCTUnwrap(URL(string: "\(TaskDeepLink.scheme)://task/42?server=https://mock.vikunja.io/base"))
            )
        for cached in [false, true] {
            let state = await app()
            if cached {
                state.tasks = [VTask(id: 42, title: "Old title", done: false, priority: 0, projectId: 1)]
            }
            MockURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(
                    request.url?.absoluteString,
                    "https://mock.vikunja.io/base" + VikunjaAPI.path("/tasks/42")
                )
                let json = #"{"id":42,"title":"Fresh task","done":false,"priority":0,"project_id":1}"#
                    .data(using: .utf8)!
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
            }
            let task = try await state.loadLinkedTask(link)
            XCTAssertEqual(task.title, "Fresh task")
            XCTAssertEqual(state.tasks.filter { $0.id == 42 }.count, 1)
        }
    }

    func testWrongServerNeverContactsNetwork() async throws {
        let state = await app()
        let link =
            try TaskDeepLink(
                url: XCTUnwrap(URL(string: "\(TaskDeepLink.scheme)://task/42?server=https://other.example.com"))
            )
        do { _ = try await state.loadLinkedTask(link)
            XCTFail("Expected server mismatch")
        } catch { XCTAssertEqual(error.localizedDescription, TaskLinkFailure.wrongServer.localizedDescription) }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testDeletedAndInaccessibleTasksAreNotPresented() async throws {
        for code in [403, 404] {
            let state = await app()
            MockURLProtocol.requestHandler = { request in
                (MockURLProtocol.makeResponse(statusCode: code, url: request.url), Data())
            }
            let link =
                try TaskDeepLink(
                    url: XCTUnwrap(URL(string: "\(TaskDeepLink.scheme)://task/42?server=https://mock.vikunja.io/base"))
                )
            do { _ = try await state.loadLinkedTask(link)
                XCTFail("Expected unavailable task")
            } catch { XCTAssertEqual(error.localizedDescription, TaskLinkFailure.unavailable.localizedDescription) }
            XCTAssertTrue(state.tasks.isEmpty)
        }
    }
}
