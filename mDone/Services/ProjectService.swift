import Foundation

actor ProjectService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchProjects(page: Int = 1, includeArchived: Bool = false) async throws -> [Project] {
        try await apiClient.fetch(Endpoint.projects(page: page, includeArchived: includeArchived))
    }

    func fetchProject(id: Int64) async throws -> Project {
        try await apiClient.fetch(Endpoint.project(id: id))
    }

    func fetchProjectViews(projectId: Int64) async throws -> [ProjectView] {
        try await apiClient.fetch(Endpoint.projectViews(projectId: projectId))
    }

    /// Fetches the kanban buckets (columns) for a project view, each with its
    /// embedded tasks. Uses the view *tasks* endpoint: for a kanban view it
    /// returns bucket objects with tasks inside (the `/buckets` endpoint stopped
    /// embedding tasks in Vikunja v0.24).
    func fetchBuckets(projectId: Int64, viewId: Int64) async throws -> [Bucket] {
        try await apiClient.fetch(Endpoint.kanbanBuckets(projectId: projectId, viewId: viewId))
    }

    func createProject(_ request: ProjectCreateRequest) async throws -> Project {
        try await apiClient.send(Endpoint.createProject(), body: request)
    }

    func updateProject(id: Int64, request: ProjectUpdateRequest) async throws -> Project {
        try await apiClient.send(Endpoint.updateProject(id: id), body: request)
    }

    func deleteProject(id: Int64) async throws {
        try await apiClient.delete(Endpoint.deleteProject(id: id))
    }
}
