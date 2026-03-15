import Foundation

actor TaskService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchAllTasks(page: Int = 1, perPage: Int = 50) async throws -> [VTask] {
        try await apiClient.fetch(Endpoint.allTasks(page: page, perPage: perPage))
    }

    func fetchTask(id: Int64) async throws -> VTask {
        try await apiClient.fetch(Endpoint.task(id: id))
    }

    func fetchProjectTasks(projectId: Int64, viewId: Int64, page: Int = 1) async throws -> [VTask] {
        try await apiClient.fetch(Endpoint.projectTasks(projectId: projectId, viewId: viewId, page: page))
    }

    func createTask(projectId: Int64, request: TaskCreateRequest) async throws -> VTask {
        try await apiClient.send(Endpoint.createTask(projectId: projectId), body: request)
    }

    func updateTask(id: Int64, request: TaskUpdateRequest) async throws -> VTask {
        try await apiClient.send(Endpoint.updateTask(id: id), body: request)
    }

    func toggleDone(task: VTask) async throws -> VTask {
        let request = TaskUpdateRequest(done: !task.done)
        return try await apiClient.send(Endpoint.updateTask(id: task.id), body: request)
    }

    func deleteTask(id: Int64) async throws {
        try await apiClient.delete(Endpoint.deleteTask(id: id))
    }

    func updatePosition(taskId: Int64, position: Double, viewId: Int64) async throws {
        let request = TaskPositionRequest(position: position, projectViewId: viewId)
        try await apiClient.sendExpectingEmpty(Endpoint.updateTaskPosition(taskId: taskId), body: request)
    }
}

struct TaskPositionRequest: Encodable {
    var position: Double
    var projectViewId: Int64
}
