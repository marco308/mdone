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
    ///
    /// `page`/`per_page` paginate the tasks *inside* each bucket, not the
    /// buckets themselves: every page repeats all the buckets, each carrying
    /// the next slice of its tasks. That makes `fetchAllPages` the wrong tool
    /// here, because `x-pagination-total-pages` counts the buckets and so
    /// reads `1` however many pages of tasks there are. Following it stopped
    /// after one request and capped every column at `per_page` cards, with
    /// nothing on the board to say cards were missing (issue #141).
    ///
    /// So page on the buckets' own `count` instead, and stop as soon as a page
    /// brings nothing new. That second condition is what protects against
    /// servers that omit `count` or ignore `page` entirely.
    func fetchBuckets(projectId: Int64, viewId: Int64, perPage: Int = 100) async throws -> [Bucket] {
        var buckets: [Bucket] = try await apiClient.fetch(
            Endpoint.kanbanBuckets(projectId: projectId, viewId: viewId, page: 1, perPage: perPage)
        )
        var seenTaskIds = Set(buckets.flatMap { ($0.tasks ?? []).map(\.id) })
        var page = 2

        while Self.hasIncompleteBucket(buckets) {
            let nextPage: [Bucket] = try await apiClient.fetch(
                Endpoint.kanbanBuckets(projectId: projectId, viewId: viewId, page: page, perPage: perPage)
            )

            var gainedTasks = false
            for bucket in nextPage {
                // Dedupe by task id: a bucket whose tasks all arrived already
                // repeats them rather than returning nothing.
                let newTasks = (bucket.tasks ?? []).filter { seenTaskIds.insert($0.id).inserted }
                guard !newTasks.isEmpty else { continue }
                gainedTasks = true
                if let index = buckets.firstIndex(where: { $0.id == bucket.id }) {
                    buckets[index].tasks = (buckets[index].tasks ?? []) + newTasks
                } else {
                    var added = bucket
                    added.tasks = newTasks
                    buckets.append(added)
                }
            }

            guard gainedTasks else { break }
            page += 1
        }

        return buckets
    }

    /// Whether any bucket holds fewer tasks than the server says it has. A
    /// bucket without a `count` counts as possibly incomplete: one more request
    /// settles it, and the caller's "nothing new" check ends the loop.
    private static func hasIncompleteBucket(_ buckets: [Bucket]) -> Bool {
        buckets.contains { bucket in
            guard let count = bucket.count else { return true }
            return (bucket.tasks?.count ?? 0) < count
        }
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
