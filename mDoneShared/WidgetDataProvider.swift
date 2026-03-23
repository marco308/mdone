import Foundation

/// Lightweight API client for widget use. Reads credentials from shared App Group UserDefaults
/// and fetches tasks directly from the Vikunja REST API without depending on the main app module.
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
        SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey)
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

        let widgetData = try await WidgetData(
            todayTasks: today,
            upcomingTasks: upcoming,
            overdueTasks: overdue,
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
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let startStr = formatDate(startOfDay)
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
        let filter = "due_date < \"\(nowStr)\" && due_date > \"0001-01-02T00:00:00Z\" && done = false"

        return try await fetchTasks(
            filter: filter,
            sortBy: "due_date",
            orderBy: "asc",
            perPage: 10
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
        let done: Bool
        let dueDate: Date?
        let priority: Int64
        let projectId: Int64
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

        return apiTasks.map { task in
            let effectiveDueDate = effectiveDate(task.dueDate)
            let overdue: Bool = {
                guard let due = effectiveDueDate, !task.done else { return false }
                return due < now
            }()

            return WidgetTask(
                id: task.id,
                title: task.title,
                done: task.done,
                dueDate: effectiveDueDate,
                priority: Int(task.priority),
                projectId: task.projectId,
                projectTitle: nil,
                isOverdue: overdue
            )
        }
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
