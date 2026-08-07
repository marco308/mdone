import Foundation

actor ProjectService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Fetches every project, following pagination to the last page.
    ///
    /// A single request only ever returns one page, so anyone with more
    /// projects than the page size lost the rest silently (issue #139).
    /// Raising `per_page` alone is not enough: Vikunja clamps it server-side
    /// to `maxitemsperpage` (50 by default), so the loop is what guarantees
    /// completeness.
    func fetchProjects(perPage: Int = 100, includeArchived: Bool = false) async throws -> [Project] {
        let paged: [Project] = try await apiClient.fetchAllPages({ page, pp in
            Endpoint.projects(page: page, perPage: pp, includeArchived: includeArchived)
        }, perPage: perPage)

        // Vikunja appends its pseudo-projects (negative ids, e.g. -2 "My Open
        // Tasks") to *every* page and leaves them out of the pagination count,
        // so combining pages hands back one copy per page. `Project` is
        // Identifiable and the sidebar renders it in a ForEach, where duplicate
        // ids are undefined behaviour. Keep the first occurrence of each id.
        var seen = Set<Int64>()
        return paged.filter { seen.insert($0.id).inserted }
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
