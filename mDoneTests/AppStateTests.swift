import XCTest
@testable import mDone

@MainActor
final class AppStateTests: XCTestCase {
    // MARK: - uniquedById

    func testUniquedByIdRemovesDuplicates() {
        let tasks = [
            VTask(id: 1, title: "First", done: false, priority: 0, projectId: 10),
            VTask(id: 2, title: "Second", done: false, priority: 0, projectId: 10),
            VTask(id: 1, title: "First (dup)", done: false, priority: 0, projectId: 10),
            VTask(id: 3, title: "Third", done: false, priority: 0, projectId: 10)
        ]

        let unique = AppState.uniquedById(tasks)

        XCTAssertEqual(unique.map(\.id), [1, 2, 3], "Should preserve order and keep the first occurrence")
        XCTAssertEqual(unique[0].title, "First", "Should keep the first occurrence, not a later duplicate")
    }

    func testUniquedByIdPreservesOrderWhenAllUnique() {
        let tasks = [
            VTask(id: 5, title: "A", done: false, priority: 0, projectId: 10),
            VTask(id: 3, title: "B", done: false, priority: 0, projectId: 10),
            VTask(id: 7, title: "C", done: false, priority: 0, projectId: 10)
        ]

        let unique = AppState.uniquedById(tasks)

        XCTAssertEqual(unique.map(\.id), [5, 3, 7])
    }

    func testUniquedByIdEmpty() {
        XCTAssertEqual(AppState.uniquedById([]).count, 0)
    }

    // MARK: - tasksForProject with duplicate-cache regression (issue #54)

    /// Reproduces the crash that issue #54 reported. Before the fix, `tasksForProject`
    /// fed the cached task list (which can contain duplicate ids when Vikunja's
    /// view-tasks endpoint returns the same task more than once) into
    /// `Dictionary(uniqueKeysWithValues:)`, which traps with a `_MergeError` and
    /// brings down the whole UI.
    func testTasksForProjectDoesNotCrashWithDuplicateCache() {
        let projectId: Int64 = 99
        let appState = AppState()

        appState.tasks = [
            VTask(id: 1, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 3, title: "C", done: false, priority: 0, projectId: projectId)
        ]

        // Simulate the bad cache state Vikunja can produce: id 1 appears twice.
        appState.projectTaskCache[projectId] = [
            VTask(id: 1, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 3, title: "C", done: false, priority: 0, projectId: projectId),
            VTask(id: 1, title: "A (dup row)", done: false, priority: 0, projectId: projectId)
        ]

        // Before the fix this call traps. After the fix it returns the three tasks
        // ordered by their first appearance in the cache.
        let result = appState.tasksForProject(projectId)

        XCTAssertEqual(result.map(\.id), [1, 2, 3])
    }

    func testTasksForProjectOrdersFromCachePosition() {
        let projectId: Int64 = 42
        let appState = AppState()

        appState.tasks = [
            VTask(id: 10, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 20, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 30, title: "C", done: false, priority: 0, projectId: projectId)
        ]

        // Cache order is reversed compared to the canonical tasks array.
        appState.projectTaskCache[projectId] = [
            VTask(id: 30, title: "C", done: false, priority: 0, projectId: projectId),
            VTask(id: 20, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 10, title: "A", done: false, priority: 0, projectId: projectId)
        ]

        XCTAssertEqual(appState.tasksForProject(projectId).map(\.id), [30, 20, 10])
    }

    func testTasksForProjectExcludesDoneTasks() {
        let projectId: Int64 = 7
        let appState = AppState()

        appState.tasks = [
            VTask(id: 1, title: "Open", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "Done", done: true, priority: 0, projectId: projectId),
            VTask(id: 3, title: "Other project", done: false, priority: 0, projectId: 999)
        ]

        XCTAssertEqual(appState.tasksForProject(projectId).map(\.id), [1])
    }
}
