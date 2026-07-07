import Foundation

/// Lightweight API client for widget use. Reads the server URL from shared App Group UserDefaults
/// and the API token from the shared keychain item, then fetches tasks directly from the
/// Vikunja REST API without depending on the main app module.
final class WidgetDataProvider: @unchecked Sendable {
    static let shared = WidgetDataProvider()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if dateString == "0001-01-01T00:00:00Z" {
                return Date.distantPast
            }
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    // MARK: - Credentials

    private var serverURL: String? {
        SharedKeys.sharedDefaults.string(forKey: SharedKeys.serverURLKey)
    }

    private var apiToken: String? {
        SharedTokenStore.get()
    }

    var isAuthenticated: Bool {
        serverURL != nil && apiToken != nil
    }

    // MARK: - Fetch Widget Data

    /// Fetches today, upcoming, and overdue tasks and returns assembled `WidgetData`.
    func fetchWidgetData() async throws -> WidgetData {
        async let today = fetchTodayTasks()
        async let upcoming = fetchUpcomingTasks()
        async let overdue = fetchOverdueTasks()
        async let projects = fetchProjects()

        let widgetData = try await WidgetData(
            todayTasks: today,
            upcomingTasks: upcoming,
            overdueTasks: overdue,
            projects: projects,
            lastUpdated: Date()
        )

        // Cache to App Group for fallback
        cacheWidgetData(widgetData)

        return widgetData
    }

    /// Returns previously cached `WidgetData` from App Group UserDefaults, if available.
    func cachedWidgetData() -> WidgetData? {
        guard let data = SharedKeys.sharedDefaults.data(forKey: SharedKeys.widgetDataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    // MARK: - Task Queries

    private func fetchTodayTasks() async throws -> [WidgetTask] {
        let calendar = Calendar.current
        let now = Date()
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return []
        }

        // Only tasks still upcoming today — anything already past its due time is returned by
        // fetchOverdueTasks instead, otherwise the same task would appear in both lists.
        let startStr = formatDate(now)
        let endStr = formatDate(endOfDay)
        let filter = "due_date > \"\(startStr)\" && due_date < \"\(endStr)\" && done = false"

        return try await fetchTasks(
            filter: filter,
            sortBy: "due_date",
            orderBy: "asc",
            perPage: 10
        )
    }

    private func fetchUpcomingTasks() async throws -> [WidgetTask] {
        let nowStr = formatDate(Date())
        let filter = "due_date > \"\(nowStr)\" && done = false"

        return try await fetchTasks(
            filter: filter,
            sortBy: "due_date",
            orderBy: "asc",
            perPage: 10
        )
    }

    private func fetchOverdueTasks() async throws -> [WidgetTask] {
        let nowStr = formatDate(Date())
        // Inclusive lower bound: a task whose due_date is exactly now is overdue, not upcoming.
        // Pairs with fetchTodayTasks' strict `due_date > now` so every timestamp falls in one bucket.
        let filter = "due_date <= \"\(nowStr)\" && due_date > \"0001-01-02T00:00:00Z\" && done = false"

        return try await fetchTasks(
            filter: filter,
            sortBy: "due_date",
            orderBy: "asc",
            perPage: 10
        )
    }

    // MARK: - Projects & Lists

    func fetchProjects() async throws -> [WidgetProject] {
        guard let serverURL, let apiToken else { return [] }

        let baseURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = baseURL + "/api/v1/projects"
        guard let url = URL(string: urlString) else { throw WidgetDataError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }

        struct APIProject: Decodable {
            let id: Int64
            let title: String
            let hexColor: String?
        }

        let apiProjects = try decoder.decode([APIProject].self, from: data)
        return apiProjects.map { WidgetProject(id: $0.id, title: $0.title, hexColor: $0.hexColor) }
    }

    func fetchTasks(forProjectId projectId: Int64) async throws -> [WidgetTask] {
        return try await fetchTasks(
            filter: "project_id = \(projectId) && done = false",
            sortBy: "due_date",
            orderBy: "asc",
            perPage: 50
        )
    }

    // MARK: - Complete Task

    /// Marks a task as done via the Vikunja API.
    func completeTask(id: Int64) async throws {
        guard let serverURL, let apiToken else { return }

        let urlString = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/api/v1/tasks/\(id)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let body = ["done": true]
        request.httpBody = try encoder.encode(body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }
    }
    
    // MARK: - Update and Delete Tasks
    
    func deleteTask(id: Int64) async throws {
        guard let serverURL, let apiToken else { return }

        let urlString = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/api/v1/tasks/\(id)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }
    }
    
    func updateTask(id: Int64, request updateRequest: TaskUpdateRequest) async throws {
        guard let serverURL, let apiToken else { return }

        let urlString = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/api/v1/tasks/\(id)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try encoder.encode(updateRequest)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }
    }
    
    struct CreateTaskRequest: Encodable {
        let title: String
    }

    func createTask(title: String, projectId: Int64) async throws {
        guard let serverURL, let apiToken else { return }

        let urlString = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/api/v1/projects/\(projectId)/tasks"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let payload = CreateTaskRequest(title: title)
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }
    }

    // MARK: - Caching

    func cacheWidgetData(_ widgetData: WidgetData) {
        guard let data = try? JSONEncoder().encode(widgetData) else { return }
        SharedKeys.sharedDefaults.set(data, forKey: SharedKeys.widgetDataKey)
    }

    // MARK: - Private Helpers

    /// Raw API task structure matching Vikunja's JSON response (snake_case decoded automatically).
    private struct APITask: Decodable {
        let id: Int64
        let title: String
        let description: String?
        let done: Bool
        let dueDate: Date?
        let priority: Int64
        let projectId: Int64
        let hexColor: String?
    }

    private func fetchTasks(
        filter: String,
        sortBy: String,
        orderBy: String,
        perPage: Int
    ) async throws -> [WidgetTask] {
        guard let serverURL, let apiToken else { return [] }

        let baseURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var components = URLComponents(string: baseURL + "/api/v1/tasks")
        components?.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "order_by", value: orderBy),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
        ]

        guard let url = components?.url else { throw WidgetDataError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw WidgetDataError.requestFailed
        }

        let apiTasks = try decoder.decode([APITask].self, from: data)
        let now = Date()

        return apiTasks.map { apiTask in
            let effectiveDueDate = effectiveDate(apiTask.dueDate)
            let isOverdue: Bool = {
                guard let due = effectiveDueDate, !apiTask.done else { return false }
                return due < now
            }()

            return WidgetTask(
                id: apiTask.id,
                title: apiTask.title,
                description: apiTask.description ?? "",
                done: apiTask.done,
                dueDate: apiTask.dueDate,
                priority: Int(apiTask.priority),
                projectId: apiTask.projectId,
                projectTitle: nil, // Add project fetching if needed later
                hexColor: apiTask.hexColor,
                isOverdue: isOverdue
            )
        }
    }

// MARK: - Task Update Models

struct TaskUpdateRequest: Encodable {
    var title: String?
    var description: String?
    var dueDate: Date?
    var priority: Int?
}

    /// Returns nil for Vikunja's zero-date sentinel (year <= 1).
    private func effectiveDate(_ date: Date?) -> Date? {
        guard let date else { return nil }
        if Calendar.current.component(.year, from: date) <= 1 { return nil }
        return date
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum WidgetDataError: Error {
    case invalidURL
    case requestFailed
    case unauthorized
}
