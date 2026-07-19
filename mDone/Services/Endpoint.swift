import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?

    init(path: String, method: HTTPMethod = .GET, queryItems: [URLQueryItem]? = nil) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
    }

    // MARK: - Auth

    static let login = Endpoint(path: "/api/v1/login", method: .POST)

    /// Vikunja 2.0.0+ JWT refresh. Accepts the `vikunja_refresh_token` cookie
    /// (not a Bearer token) and returns a fresh short-lived JWT plus a new
    /// Set-Cookie that invalidates the previous refresh token.
    static let refreshToken = Endpoint(path: "/api/v1/user/token/refresh", method: .POST)

    // MARK: - User

    static let currentUser = Endpoint(path: "/api/v1/user")

    // MARK: - Projects

    /// Lists projects. Vikunja excludes archived projects unless `is_archived=true`
    /// is passed, in which case it returns active **and** archived projects.
    static func projects(page: Int = 1, perPage: Int = 50, includeArchived: Bool = false) -> Endpoint {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ]
        if includeArchived {
            items.append(URLQueryItem(name: "is_archived", value: "true"))
        }
        return Endpoint(path: "/api/v1/projects", queryItems: items)
    }

    static func project(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)")
    }

    static func projectViews(projectId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views")
    }

    // MARK: - Kanban Buckets

    /// Lists the buckets (columns) of a project's kanban view, with each
    /// bucket's tasks embedded.
    static func projectBuckets(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 100) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views/\(viewId)/buckets", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
    }

    /// Moves a task into a bucket. Vikunja uses POST with a body of `{ "task_id": <id> }`.
    static func moveTaskToBucket(projectId: Int64, viewId: Int64, bucketId: Int64) -> Endpoint {
        Endpoint(
            path: "/api/v1/projects/\(projectId)/views/\(viewId)/buckets/\(bucketId)/tasks",
            method: .POST
        )
    }

    /// Creates a project. Vikunja uses PUT (not POST) for creation.
    static func createProject() -> Endpoint {
        Endpoint(path: "/api/v1/projects", method: .PUT)
    }

    /// Updates a project (title, description, colour, favourite, archived).
    static func updateProject(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)", method: .POST)
    }

    /// Deletes a project. Vikunja cascades this to all tasks and descendant projects.
    static func deleteProject(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)", method: .DELETE)
    }

    // MARK: - Tasks

    static func allTasks(
        page: Int = 1,
        perPage: Int = 50,
        filter: String? = nil,
        search: String? = nil,
        sortBy: String? = nil,
        orderBy: String? = nil
    ) -> Endpoint {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ]
        if let filter, !filter.isEmpty {
            items.append(URLQueryItem(name: "filter", value: filter))
        }
        if let search, !search.isEmpty {
            items.append(URLQueryItem(name: "s", value: search))
        }
        if let sortBy, !sortBy.isEmpty {
            items.append(URLQueryItem(name: "sort_by", value: sortBy))
        }
        if let orderBy, !orderBy.isEmpty {
            items.append(URLQueryItem(name: "order_by", value: orderBy))
        }
        // Ask the server to embed each task's subtask relations. Current
        // Vikunja (2.x) populates `related_tasks` in list responses anyway,
        // but versions that gate it behind `expand` need this to be explicit.
        items.append(URLQueryItem(name: "expand", value: "subtasks"))
        return Endpoint(path: "/api/v1/tasks", queryItems: items)
    }

    static func projectTasks(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views/\(viewId)/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "expand", value: "subtasks"),
        ])
    }

    static func createTask(projectId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/tasks", method: .PUT)
    }

    static func updateTask(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(id)", method: .POST)
    }

    static func deleteTask(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(id)", method: .DELETE)
    }

    static func task(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(id)")
    }

    // MARK: - Task Relations

    /// Creates a relation between two tasks. Vikunja uses PUT (not POST) for
    /// creation, with a body of `{ "other_task_id": <id>, "relation_kind": "<kind>" }`.
    /// The inverse relation (e.g. `parenttask` on the other task when creating
    /// a `subtask`) is created server-side automatically.
    static func createTaskRelation(taskId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskId)/relations", method: .PUT)
    }

    /// Removes a relation; the server also removes the inverse relation from
    /// the other task.
    static func deleteTaskRelation(taskId: Int64, relationKind: String, otherTaskId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskId)/relations/\(relationKind)/\(otherTaskId)", method: .DELETE)
    }

    // MARK: - Labels

    static func labels(page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/labels", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
    }

    /// Creates a label. Vikunja uses PUT (not POST) for creation.
    static func createLabel() -> Endpoint {
        Endpoint(path: "/api/v1/labels", method: .PUT)
    }

    /// Associates a label with a task. Body: `{ "label_id": <id> }`.
    static func addLabelToTask(taskId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskId)/labels", method: .PUT)
    }

    /// Removes a label association from a task.
    static func removeLabelFromTask(taskId: Int64, labelId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskId)/labels/\(labelId)", method: .DELETE)
    }

    // MARK: - Notifications

    static func notifications(page: Int = 1) -> Endpoint {
        Endpoint(path: "/api/v1/notifications", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
        ])
    }

    static func markNotificationRead(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/notifications/\(id)", method: .POST)
    }

    static let markAllNotificationsRead = Endpoint(path: "/api/v1/notifications", method: .POST)

    // MARK: - Task Position

    static func updateTaskPosition(taskId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/tasks/\(taskId)/position", method: .POST)
    }
}
