import Foundation

actor ProjectService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchProjects(page: Int = 1) async throws -> [Project] {
        try await apiClient.fetch(Endpoint.projects(page: page))
    }

    func fetchProject(id: Int64) async throws -> Project {
        try await apiClient.fetch(Endpoint.project(id: id))
    }

    func fetchProjectViews(projectId: Int64) async throws -> [ProjectView] {
        try await apiClient.fetch(Endpoint.projectViews(projectId: projectId))
    }
}
