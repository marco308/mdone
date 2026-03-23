import XCTest
@testable import mDone

final class SyncServiceTests: XCTestCase {
    // MARK: - CachedTask Round Trip

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

    // MARK: - CachedTask with Labels

    func testCachedTaskPreservesLabels() {
        let labels = [
            VLabel(id: 1, title: "Bug", hexColor: "#FF0000"),
            VLabel(id: 2, title: "Feature", hexColor: "#00FF00"),
        ]

        let task = VTask(
            id: 1,
            title: "Labeled Task",
            done: false,
            priority: 2,
            projectId: 1,
            labels: labels
        )

        let cached = CachedTask(from: task)
        XCTAssertNotNil(cached.labelsData)

        let restored = cached.toVTask()
        XCTAssertEqual(restored.labels?.count, 2)
        XCTAssertEqual(restored.labels?[0].title, "Bug")
        XCTAssertEqual(restored.labels?[1].title, "Feature")
    }

    func testCachedTaskWithNoLabels() {
        let task = VTask(id: 1, title: "No Labels", done: false, priority: 0, projectId: 1)

        let cached = CachedTask(from: task)
        // labelsData may contain encoded null (4 bytes) since JSONEncoder encodes nil as "null"

        let restored = cached.toVTask()
        // Even if labelsData is non-nil, decoding "null" as [VLabel] fails, so restored labels should be nil
        XCTAssertNil(restored.labels)
    }

    // MARK: - CachedTask Update

    func testCachedTaskUpdate() {
        let originalTask = VTask(
            id: 1,
            title: "Original",
            description: "Original desc",
            done: false,
            priority: 1,
            projectId: 1,
            hexColor: "#000000"
        )

        let cached = CachedTask(from: originalTask)

        let updatedTask = VTask(
            id: 1,
            title: "Updated",
            description: "Updated desc",
            done: true,
            priority: 5,
            projectId: 2,
            hexColor: "#FFFFFF",
            percentDone: 1.0,
            isFavorite: true
        )

        cached.update(from: updatedTask)

        XCTAssertEqual(cached.title, "Updated")
        XCTAssertEqual(cached.taskDescription, "Updated desc")
        XCTAssertTrue(cached.done)
        XCTAssertEqual(cached.priority, 5)
        XCTAssertEqual(cached.projectId, 2)
        XCTAssertEqual(cached.hexColor, "#FFFFFF")
        XCTAssertEqual(cached.percentDone, 1.0)
        XCTAssertTrue(cached.isFavorite)
    }

    // MARK: - CachedProject Update

    func testCachedProjectUpdate() {
        let originalProject = Project(
            id: 1,
            title: "Original",
            description: "Desc",
            hexColor: "#000000",
            isArchived: false,
            isFavorite: false,
            position: 1.0
        )

        let cached = CachedProject(from: originalProject)

        let updatedProject = Project(
            id: 1,
            title: "Updated",
            description: "New Desc",
            hexColor: "#FFFFFF",
            isArchived: true,
            isFavorite: true,
            position: 2.0
        )

        cached.update(from: updatedProject)

        XCTAssertEqual(cached.title, "Updated")
        XCTAssertEqual(cached.projectDescription, "New Desc")
        XCTAssertEqual(cached.hexColor, "#FFFFFF")
        XCTAssertTrue(cached.isArchived)
        XCTAssertTrue(cached.isFavorite)
        XCTAssertEqual(cached.position, 2.0)
    }

    // MARK: - CachedProject with Minimal Fields

    func testCachedProjectMinimalFields() {
        let project = Project(id: 1, title: "Minimal")

        let cached = CachedProject(from: project)
        XCTAssertEqual(cached.id, 1)
        XCTAssertEqual(cached.title, "Minimal")
        XCTAssertNil(cached.projectDescription)
        XCTAssertNil(cached.hexColor)
        XCTAssertFalse(cached.isArchived)
        XCTAssertFalse(cached.isFavorite)
        XCTAssertNil(cached.position)

        let restored = cached.toProject()
        XCTAssertEqual(restored.id, 1)
        XCTAssertEqual(restored.title, "Minimal")
        XCTAssertNil(restored.description)
        XCTAssertNil(restored.hexColor)
        XCTAssertEqual(restored.isArchived, false)
        XCTAssertEqual(restored.isFavorite, false)
    }

    // MARK: - CachedLabel Round Trip

    func testCachedLabelRoundTrip() {
        let label = VLabel(
            id: 5,
            title: "Important",
            hexColor: "#FF4444",
            description: "Important items"
        )

        let cached = CachedLabel(from: label)
        XCTAssertEqual(cached.id, 5)
        XCTAssertEqual(cached.title, "Important")
        XCTAssertEqual(cached.hexColor, "#FF4444")
        XCTAssertEqual(cached.labelDescription, "Important items")

        let restored = cached.toLabel()
        XCTAssertEqual(restored.id, 5)
        XCTAssertEqual(restored.title, "Important")
        XCTAssertEqual(restored.hexColor, "#FF4444")
        XCTAssertEqual(restored.description, "Important items")
    }

    func testCachedLabelMinimalFields() {
        let label = VLabel(id: 1, title: "Simple")

        let cached = CachedLabel(from: label)
        XCTAssertEqual(cached.id, 1)
        XCTAssertEqual(cached.title, "Simple")
        XCTAssertNil(cached.hexColor)
        XCTAssertNil(cached.labelDescription)

        let restored = cached.toLabel()
        XCTAssertEqual(restored.id, 1)
        XCTAssertEqual(restored.title, "Simple")
        XCTAssertNil(restored.hexColor)
        XCTAssertNil(restored.description)
    }

    // MARK: - PendingOperation

    func testPendingOperationInitialization() {
        let operation = PendingOperation(
            endpointPath: "/api/v1/tasks/1",
            method: "POST",
            bodyData: "{\"done\": true}".data(using: .utf8)
        )

        XCTAssertEqual(operation.endpointPath, "/api/v1/tasks/1")
        XCTAssertEqual(operation.method, "POST")
        XCTAssertNotNil(operation.bodyData)
        XCTAssertNotNil(operation.id)
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertFalse(operation.failed)
    }

    func testPendingOperationWithoutBody() {
        let operation = PendingOperation(
            endpointPath: "/api/v1/tasks/1",
            method: "DELETE"
        )

        XCTAssertEqual(operation.method, "DELETE")
        XCTAssertNil(operation.bodyData)
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertFalse(operation.failed)
    }

    func testPendingOperationRetryTracking() {
        let operation = PendingOperation(
            endpointPath: "/api/v1/tasks/1",
            method: "POST"
        )

        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertFalse(operation.failed)

        operation.retryCount += 1
        XCTAssertEqual(operation.retryCount, 1)

        operation.retryCount += 1
        operation.retryCount += 1
        XCTAssertEqual(operation.retryCount, 3)

        operation.failed = true
        XCTAssertTrue(operation.failed)
    }
}
