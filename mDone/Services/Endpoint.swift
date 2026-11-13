import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
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

    /// An endpoint under the Vikunja API prefix: `api: "/tasks/1"` is
    /// `/api/v2/tasks/1`. Every Vikunja endpoint below is built this way so the
    /// API version is named once, in `VikunjaAPI`.
    init(api route: String, method: HTTPMethod = .GET, queryItems: [URLQueryItem]? = nil) {
        self.init(path: VikunjaAPI.path(route), method: method, queryItems: queryItems)
    }

    // MARK: - Auth

    static let login = Endpoint(api: "/login", method: .POST)

    /// Vikunja 2.0.0+ JWT refresh. Accepts the `vikunja_refresh_token` cookie
    /// (not a Bearer token) and returns a fresh short-lived JWT plus a new
    /// Set-Cookie that invalidates the previous refresh token.
    static let refreshToken = Endpoint(api: "/user/token/refresh", method: .POST)

    /// Instance metadata, including which auth methods the server offers.
    /// Unauthenticated: this is what the login screen reads before it knows
    /// anything about the server.
    static let info = Endpoint(api: "/info")

    /// The same document from the v1 API, for a server too old to have v2.
    /// Reading its version is how the app can say "update your server"
    /// instead of failing with a bare 404 (#291).
    static let legacyInfo = Endpoint(path: VikunjaAPI.legacyPath("/info"))

    /// Exchanges an OIDC authorization code for a Vikunja JWT. `provider` is
    /// the provider `key` from `/info`, not its display name.
    ///
    /// This is the one request still made to the v1 API: v2 has no OIDC
    /// callback (checked against Vikunja 2.4.0 and 2.8.0). The JWT it returns
    /// works on v2 like any other.
    ///
    /// The key is percent-encoded because it comes from the server rather than
    /// from us, and `APIClient.buildRequest` concatenates paths and calls
    /// `URL(string:)` without escaping. An unescaped key containing `/` or `..`
    /// would move this POST to a different path, and this is the request that
    /// carries the authorization code.
    static func openIDCallback(provider: String) -> Endpoint {
        Endpoint(
            path: VikunjaAPI.legacyPath("/auth/openid/\(pathSegment(provider))/callback"),
            method: .POST
        )
    }

    /// Percent-encodes a single path segment. Deliberately narrower than
    /// `.urlPathAllowed`, which permits `/`, and narrower than RFC 3986's
    /// unreserved set, which permits `.` and would leave `..` intact.
    static func pathSegment(_ raw: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~"))
        return raw.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
    }

    // MARK: - User

    static let currentUser = Endpoint(api: "/user")

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
        return Endpoint(api: "/projects", queryItems: items)
    }

    static func project(id: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(id)")
    }

    static func projectViews(projectId: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(projectId)/views")
    }

    /// The users who can see a project, through a direct share, a team or as
    /// its owner: the people a task in it can be assigned to. Unlike
    /// `/projects/{id}/users` it leaves out email addresses and needs only read
    /// access. Answers in the list envelope but in a single page.
    static func projectUsers(projectId: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(projectId)/users/search")
    }

    // MARK: - Kanban Buckets

    /// Lists the buckets (columns) of a project's kanban view, with each
    /// bucket's tasks embedded. `/views/{view}/buckets` returns bucket
    /// metadata only, and `/views/{view}/tasks` a flat task list.
    ///
    /// Upstream documents this route as not paginated, but 2.4.0 and 2.8.0
    /// both still apply `page`/`per_page` to the tasks *within each bucket*:
    /// every bucket is always returned, each with one slice of its tasks. The
    /// envelope's `total` counts buckets, so it says nothing about how many
    /// pages of tasks are waiting (issue #141).
    static func kanbanBuckets(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(api: "/projects/\(projectId)/views/\(viewId)/buckets/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
    }

    /// Moves a task into a bucket: PUT with a body of `{ "task_id": <id> }`.
    static func moveTaskToBucket(projectId: Int64, viewId: Int64, bucketId: Int64) -> Endpoint {
        Endpoint(
            api: "/projects/\(projectId)/views/\(viewId)/buckets/\(bucketId)/tasks",
            method: .PUT
        )
    }

    /// Creates a project. In v2 creates are POST and updates are PUT, the
    /// reverse of v1.
    static func createProject() -> Endpoint {
        Endpoint(api: "/projects", method: .POST)
    }

    /// Replaces a project (title, description, colour, favourite, archived).
    static func updateProject(id: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(id)", method: .PUT)
    }

    /// Deletes a project. Vikunja cascades this to all tasks and descendant projects.
    static func deleteProject(id: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(id)", method: .DELETE)
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
            items.append(URLQueryItem(name: "q", value: search))
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
        return Endpoint(api: "/tasks", queryItems: items)
    }

    static func projectTasks(projectId: Int64, viewId: Int64, page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(api: "/projects/\(projectId)/views/\(viewId)/tasks", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "expand", value: "subtasks"),
        ])
    }

    static func createTask(projectId: Int64) -> Endpoint {
        Endpoint(api: "/projects/\(projectId)/tasks", method: .POST)
    }

    /// Replaces the whole task: a field left out of the body is cleared, as it
    /// was with v1's update. PATCH is the partial update (#292).
    static func updateTask(id: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(id)", method: .PUT)
    }

    static func deleteTask(id: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(id)", method: .DELETE)
    }

    static func task(id: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(id)")
    }

    // MARK: - Task Relations

    /// Creates a relation between two tasks, with a body of
    /// `{ "other_task_id": <id>, "relation_kind": "<kind>" }`.
    /// The inverse relation (e.g. `parenttask` on the other task when creating
    /// a `subtask`) is created server-side automatically.
    static func createTaskRelation(taskId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/relations", method: .POST)
    }

    /// Removes a relation; the server also removes the inverse relation from
    /// the other task.
    static func deleteTaskRelation(taskId: Int64, relationKind: String, otherTaskId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/relations/\(relationKind)/\(otherTaskId)", method: .DELETE)
    }

    // MARK: - Task Assignees

    /// Replaces every assignee of a task in one call. Body:
    /// `{ "assignees": [{ "id": <userId> }] }`; an empty list unassigns all.
    /// Vikunja answers 7003 when a user cannot see the task's project.
    static func setTaskAssignees(taskId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/assignees/bulk", method: .PUT)
    }

    // MARK: - Labels

    static func labels(page: Int = 1, perPage: Int = 50) -> Endpoint {
        Endpoint(api: "/labels", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ])
    }

    static func createLabel() -> Endpoint {
        Endpoint(api: "/labels", method: .POST)
    }

    /// Associates a label with a task. Body: `{ "label_id": <id> }`.
    static func addLabelToTask(taskId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/labels", method: .POST)
    }

    /// Removes a label association from a task.
    static func removeLabelFromTask(taskId: Int64, labelId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/labels/\(labelId)", method: .DELETE)
    }

    // MARK: - Notifications

    static func notifications(page: Int = 1) -> Endpoint {
        Endpoint(api: "/notifications", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
        ])
    }

    static func markNotificationRead(id: Int64) -> Endpoint {
        Endpoint(api: "/notifications/\(id)", method: .PUT)
    }

    static let markAllNotificationsRead = Endpoint(api: "/notifications", method: .POST)

    // MARK: - Task Position

    static func updateTaskPosition(taskId: Int64) -> Endpoint {
        Endpoint(api: "/tasks/\(taskId)/position", method: .PUT)
    }
}
