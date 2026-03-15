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

    // MARK: - User
    static let currentUser = Endpoint(path: "/api/v1/user")

    // MARK: - Projects
    static func projects(page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/projects", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ])
    }

    static func project(id: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(id)")
    }

    static func projectViews(projectId: Int64) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views")
    }

    // MARK: - Tasks
    static func allTasks(page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ])
    }

    static func projectTasks(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/projects/\(projectId)/views/\(viewId)/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
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
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ])
    }

    // MARK: - Notifications
    static let notifications = Endpoint(path: "/api/v1/notifications")
    static let markAllNotificationsRead = Endpoint(path: "/api/v1/notifications", method: .POST)
}
