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
        return Endpoint(path: "/api/v1/tasks", queryItems: items)
    }

    static func projectTasks(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views/\(viewId)/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
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

    // MARK: - Labels

    static func labels(page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/labels", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
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
