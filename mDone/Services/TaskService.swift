import Foundation

actor TaskService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchAllTasks(perPage: Int = 100) async throws -> [VTask] {
        try await apiClient.fetchAllPages({ page, pp in
            Endpoint.allTasks(page: page, perPage: pp)
        }, perPage: perPage)
    }

    func fetchTask(id: Int64) async throws -> VTask {
        try await apiClient.fetch(Endpoint.task(id: id))
    }

    /// Fetches a project view's tasks in their stored view order, following
    /// pagination to the last page.
    ///
    /// The order matters more than the tasks here: `AppState` keeps the global
    /// task list as its source of truth and uses this response only to order a
    /// project's list. Reading one page left everything past the 50th task out
    /// of the order map, so those tasks fell to the bottom of the list in
    /// arbitrary order (issue #141).
    func fetchProjectTasks(projectId: Int64, viewId: Int64, perPage: Int = 100) async throws -> [VTask] {
        try await apiClient.fetchAllPages({ page, pp in
            Endpoint.projectTasks(projectId: projectId, viewId: viewId, page: page, perPage: pp)
        }, perPage: perPage)
    }

    func createTask(projectId: Int64, request: TaskCreateRequest) async throws -> VTask {
        try await apiClient.send(Endpoint.createTask(projectId: projectId), body: request)
    }

    func updateTask(id: Int64, request: TaskUpdateRequest) async throws -> VTask {
        try await apiClient.send(Endpoint.updateTask(id: id), body: request)
    }

    func deleteTask(id: Int64) async throws {
        try await apiClient.delete(Endpoint.deleteTask(id: id))
    }

    func updatePosition(taskId: Int64, position: Double, viewId: Int64) async throws {
        let request = TaskPositionRequest(position: position, projectViewId: viewId)
        try await apiClient.sendExpectingEmpty(Endpoint.updateTaskPosition(taskId: taskId), body: request)
    }

    /// Links `otherTaskId` to `taskId` with the given relation kind, e.g.
    /// `.subtask` makes `otherTaskId` a subtask of `taskId`. The server creates
    /// the inverse relation on the other task automatically.
    @discardableResult
    func createRelation(taskId: Int64, otherTaskId: Int64, kind: RelationKind) async throws -> TaskRelation {
        let request = TaskRelationRequest(otherTaskId: otherTaskId, relationKind: kind)
        return try await apiClient.send(Endpoint.createTaskRelation(taskId: taskId), body: request)
    }

    /// Removes the `kind` relation between `taskId` and `otherTaskId`; the
    /// server drops the inverse relation as well.
    func deleteRelation(taskId: Int64, otherTaskId: Int64, kind: RelationKind) async throws {
        try await apiClient.delete(
            Endpoint.deleteTaskRelation(taskId: taskId, relationKind: kind.rawValue, otherTaskId: otherTaskId)
        )
    }

    /// Moves a task into a kanban bucket (column) within a project view.
    func moveTaskToBucket(taskId: Int64, projectId: Int64, viewId: Int64, bucketId: Int64) async throws {
        let request = TaskBucketRequest(taskId: taskId)
        try await apiClient.sendExpectingEmpty(
            Endpoint.moveTaskToBucket(projectId: projectId, viewId: viewId, bucketId: bucketId),
            body: request
        )
    }
}

struct TaskPositionRequest: Encodable {
    var position: Double
    var projectViewId: Int64
}
