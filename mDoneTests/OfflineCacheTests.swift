import SwiftData
import XCTest
@testable import mDone

/// Covers the offline path reported in issue #144: the app advertised offline
/// caching but never wrote to or read from the cache, so launching without a
/// reachable server sat on a blocking loading overlay and then showed an empty
/// list.
@MainActor
final class OfflineCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CachedTask.self,
            CachedProject.self,
            CachedLabel.self,
            PendingOperation.self,
            FocusRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSyncService(container: ModelContainer) async -> SyncService {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return SyncService(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            modelContainer: container
        )
    }

    /// An `AppState` whose task/project/label services all talk to
    /// `MockURLProtocol`, wired to `sync` and a monitor pinned to `connected`.
    private func makeAppState(sync: SyncService, connected: Bool) async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
        state.configureSyncService(sync, networkMonitor: NetworkMonitor(stubbedConnection: connected))
        return state
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Serves one page of tasks, projects and labels, keyed off the request path.
    private func serveFullSync() {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let body: Any = if path.contains("/labels") {
                [["id": 7, "title": "Current"]]
            } else if path.contains("/projects") {
                [["id": 3, "title": "Work"]]
            } else {
                [["id": 1, "title": "Cached task", "done": false, "priority": 0, "project_id": 3]]
            }
            let response = MockURLProtocol.makeResponse(
                statusCode: 200,
                url: request.url,
                headers: ["x-pagination-total-pages": "1"]
            )
            return (response, self.json(body))
        }
    }

    // MARK: - Cache is written on a successful refresh

    /// Before the fix `refreshAll()` wrote straight to memory: after a fully
    /// successful sync every cache table was still empty, so there was nothing
    /// to fall back to offline.
    func testSuccessfulRefreshPersistsTasksProjectsAndLabels() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: true)
        serveFullSync()

        await state.refreshAll()

        XCTAssertEqual(state.tasks.map(\.id), [1])
        XCTAssertEqual(try sync.loadCachedTasks().map(\.id), [1])
        XCTAssertEqual(try sync.loadCachedProjects().map(\.id), [3])
        XCTAssertEqual(try sync.loadCachedLabels().map(\.id), [7])
        XCTAssertFalse(state.isShowingCachedData)
    }

    // MARK: - Cache is read when offline

    /// The core repro: a synced cache plus no connectivity must still produce a
    /// populated task list.
    func testOfflineRefreshServesCachedData() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        try sync.cacheTasks([VTask(id: 1, title: "Cached task", done: false, priority: 0, projectId: 3)])
        try sync.cacheProjects([Project(id: 3, title: "Work")])
        try sync.cacheLabels([VLabel(id: 7, title: "Current")])

        let state = await makeAppState(sync: sync, connected: false)
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        await state.refreshAll()

        XCTAssertEqual(state.tasks.map(\.title), ["Cached task"])
        XCTAssertEqual(state.projects.map(\.id), [3])
        XCTAssertEqual(state.labels.map(\.id), [7])
        XCTAssertTrue(state.isShowingCachedData)
    }

    /// The infinite-spinner half of the report: offline, the refresh must not
    /// issue requests it can only lose, and must not leave `isLoading` set,
    /// which is what pins `LoadingOverlay` over the whole screen.
    func testOfflineRefreshSkipsNetworkAndLeavesNoSpinner() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        await state.refreshAll()

        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    /// An empty cache offline is a legitimate state (never synced). It must not
    /// crash or spin, just come back empty.
    func testOfflineRefreshWithEmptyCacheIsEmptyNotStuck() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)

        await state.refreshAll()

        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.isShowingCachedData)
    }

    // MARK: - Unreachable server on a working connection

    /// `NetworkMonitor` reports the device's own link, so a self-hosted server
    /// that can't be reached leaves `isOffline` false. The cached list must
    /// survive the failed refresh rather than being replaced by an empty one.
    func testUnreachableServerKeepsCachedTasksAndFlagsCachedData() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        try sync.cacheTasks([VTask(id: 1, title: "Cached task", done: false, priority: 0, projectId: 3)])

        let state = await makeAppState(sync: sync, connected: true)
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }

        await state.refreshAll()

        XCTAssertEqual(state.tasks.map(\.title), ["Cached task"])
        XCTAssertTrue(state.isShowingCachedData)
        XCTAssertFalse(state.isLoading)
    }

    /// A later successful refresh has to clear the cached-data flag so the
    /// offline banner goes away.
    func testSuccessfulRefreshClearsCachedDataFlag() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: true)

        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        await state.refreshAll()
        XCTAssertTrue(state.isShowingCachedData)

        serveFullSync()
        await state.refreshAll()
        XCTAssertFalse(state.isShowingCachedData)
        XCTAssertEqual(state.tasks.map(\.id), [1])
    }

    // MARK: - Hydration precedence

    /// Hydration must never overwrite data already fetched from the server.
    func testHydrationDoesNotClobberFresherTasks() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        try sync.cacheTasks([VTask(id: 99, title: "Stale", done: false, priority: 0, projectId: 3)])

        let state = await makeAppState(sync: sync, connected: true)
        serveFullSync()
        await state.refreshAll()

        XCTAssertEqual(state.tasks.map(\.title), ["Cached task"])
        // The refresh reconciled the cache too, so the stale row is gone.
        XCTAssertEqual(try sync.loadCachedTasks().map(\.id), [1])
    }

    // MARK: - Cache reconciliation

    func testCacheTasksRemovesRowsTheServerNoLongerReturns() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)

        try sync.cacheTasks([
            VTask(id: 1, title: "Keep", done: false, priority: 0, projectId: 1),
            VTask(id: 2, title: "Drop", done: false, priority: 0, projectId: 1),
        ])
        XCTAssertEqual(try sync.loadCachedTasks().count, 2)

        try sync.cacheTasks([VTask(id: 1, title: "Keep (renamed)", done: true, priority: 0, projectId: 1)])
        let cached = try sync.loadCachedTasks()
        XCTAssertEqual(cached.map(\.id), [1])
        XCTAssertEqual(cached.first?.title, "Keep (renamed)")
        XCTAssertEqual(cached.first?.done, true)
    }

    func testCacheLabelsReplacesTheWholeSet() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)

        try sync.cacheLabels([VLabel(id: 1, title: "One"), VLabel(id: 2, title: "Two")])
        XCTAssertEqual(try sync.loadCachedLabels().count, 2)

        try sync.cacheLabels([VLabel(id: 2, title: "Two")])
        XCTAssertEqual(try sync.loadCachedLabels().map(\.id), [2])
    }

    // MARK: - Logout

    /// A deliberate logout must not leave one account's tasks readable by the
    /// next person to sign in.
    func testLogoutClearsTheCache() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        try sync.cacheTasks([VTask(id: 1, title: "Private", done: false, priority: 0, projectId: 1)])
        try sync.cacheProjects([Project(id: 1, title: "Private project")])
        try sync.cacheLabels([VLabel(id: 1, title: "Private label")])

        let state = await makeAppState(sync: sync, connected: true)
        await state.logout()

        XCTAssertTrue(try sync.loadCachedTasks().isEmpty)
        XCTAssertTrue(try sync.loadCachedProjects().isEmpty)
        XCTAssertTrue(try sync.loadCachedLabels().isEmpty)
    }

    /// An expired session is the same account re-authenticating, so the cache
    /// stays put and the user keeps reading their tasks in the meantime.
    func testExpiredSessionKeepsTheCache() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        try sync.cacheTasks([VTask(id: 1, title: "Keep me", done: false, priority: 0, projectId: 1)])

        let state = await makeAppState(sync: sync, connected: true)
        await state.expireSession()

        XCTAssertEqual(try sync.loadCachedTasks().map(\.title), ["Keep me"])
    }
}
