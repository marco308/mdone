import XCTest
@testable import mDone

final class SyncServiceTests: XCTestCase {
    func testCachedTaskRoundTrip() {
        let task = VTask(
            id: 42,
            title: "Test Task",
            description: "A test description",
            done: false,
            dueDate: Date(),
            priority: 3,
            projectId: 1,
            hexColor: "#FF0000",
            percentDone: 0.5,
            isFavorite: true,
            created: Date(),
            updated: Date()
        )

        let cached = CachedTask(from: task)
        XCTAssertEqual(cached.id, 42)
        XCTAssertEqual(cached.title, "Test Task")
        XCTAssertEqual(cached.taskDescription, "A test description")
        XCTAssertFalse(cached.done)
        XCTAssertEqual(cached.priority, 3)
        XCTAssertEqual(cached.projectId, 1)

        let restored = cached.toVTask()
        XCTAssertEqual(restored.id, task.id)
        XCTAssertEqual(restored.title, task.title)
        XCTAssertEqual(restored.description, task.description)
        XCTAssertEqual(restored.done, task.done)
        XCTAssertEqual(restored.priority, task.priority)
    }

    func testCachedProjectRoundTrip() {
        let project = Project(
            id: 10,
            title: "Work",
            description: "Work tasks",
            hexColor: "#4772FA",
            isArchived: false,
            isFavorite: true,
            position: 1.0,
            created: Date(),
            updated: Date()
        )

        let cached = CachedProject(from: project)
        XCTAssertEqual(cached.id, 10)
        XCTAssertEqual(cached.title, "Work")
        XCTAssertTrue(cached.isFavorite)

        let restored = cached.toProject()
        XCTAssertEqual(restored.id, project.id)
        XCTAssertEqual(restored.title, project.title)
        XCTAssertEqual(restored.hexColor, project.hexColor)
        XCTAssertEqual(restored.isFavorite, true)
    }
}
