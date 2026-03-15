import Foundation
import SwiftUI

@Observable
final class AppState {
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?

    var tasks: [VTask] = []
    var projects: [Project] = []
    var labels: [VLabel] = []
    var notifications: [VNotification] = []
    var selectedProject: Project?

    var searchQuery: String = ""
    var activeFilter: TaskFilter? = nil
    var advancedFilterString: String? = nil
    var pendingOperationsCount: Int = 0
    var onTaskCompleted: ((Int64) -> Void)?
    var onTaskDeleted: ((Int64) -> Void)?

    /// Per-project ordered task lists fetched from the view endpoint (preserves positions).
    private var projectTaskCache: [Int64: [VTask]] = [:]

    var unreadNotificationCount: Int {
        notifications.filter { $0.read != true }.count
    }

    private let taskService = TaskService()
    private let projectService = ProjectService()
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared

    private var syncService: SyncService?
    private var networkMonitor: NetworkMonitor?
    private var wasDisconnected: Bool = false
    private var temporaryIdCounter: Int64 = 0

    var isOffline: Bool {
        !(networkMonitor?.isConnected ?? true)
    }

    func configureSyncService(_ syncService: SyncService, networkMonitor: NetworkMonitor) {
        self.syncService = syncService
        self.networkMonitor = networkMonitor
        wasDisconnected = !networkMonitor.isConnected
    }

    @MainActor
    func handleConnectivityChange(isConnected: Bool) {
        if isConnected, wasDisconnected {
            wasDisconnected = false
            Task { await onNetworkRestored() }
        } else if !isConnected {
            wasDisconnected = true
        }
    }

    @MainActor
    func onNetworkRestored() async {
        await syncService?.processPendingOperations()
        updatePendingCount()
        await refreshAll()
    }

    @MainActor
    private func updatePendingCount() {
        pendingOperationsCount = (try? syncService?.pendingOperationCount()) ?? 0
    }

    var overdueTasks: [VTask] {
        tasks.filter { $0.isOverdue && !$0.isDueToday }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var todayTasks: [VTask] {
        tasks.filter(\.isDueToday).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var upcomingTasks: [VTask] {
        tasks.filter { $0.isDueThisWeek && !$0.isDueToday }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var noDateTasks: [VTask] {
        tasks.filter { $0.effectiveDueDate == nil && !$0.done }
    }

    var activeTasks: [VTask] {
        tasks.filter { !$0.done }
    }

    var filteredTasks: [VTask] {
        var result = tasks

        if let activeFilter {
            result = activeFilter.apply(to: result)
        }

        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { $0.title.lowercased().contains(query) }
        }

        return result
    }

    func checkAuth() async {
        let authenticated = authService.isAuthenticated()
        if authenticated {
            await configureAPIClient()
        }
        isAuthenticated = authenticated
    }

    func configureAPIClient() async {
        guard let serverURL = authService.getServerURL(),
              let token = authService.getToken() else { return }
        await APIClient.shared.configure(serverURL: serverURL, token: token)
    }

    @MainActor
    func login(serverURL: String, token: String) async throws {
        print("[mDone] login() called with serverURL: \(serverURL)")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await APIClient.shared.configure(serverURL: serverURL, token: token)

        // Validate by fetching projects — works with both JWT and API tokens
        print("[mDone] Fetching projects to validate...")
        let projects: [Project] = try await APIClient.shared.fetch(Endpoint.projects())
        print("[mDone] Validation OK - got \(projects.count) projects")

        authService.saveServerURL(serverURL)
        authService.saveToken(token)
        print("[mDone] Credentials saved, setting isAuthenticated = true")
        isAuthenticated = true
    }

    @MainActor
    func loginWithCredentials(serverURL: String, username: String, password: String) async throws {
        print("[mDone] loginWithCredentials() called")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let url = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        await APIClient.shared.configure(serverURL: url, token: "")

        // Get JWT token via login endpoint
        let loginRequest = LoginRequest(username: username, password: password)
        let loginResponse: LoginResponse = try await APIClient.shared.send(Endpoint.login, body: loginRequest)

        // Configure with the JWT token
        await APIClient.shared.configure(serverURL: url, token: loginResponse.token)

        // Validate
        let projects: [Project] = try await APIClient.shared.fetch(Endpoint.projects())
        print("[mDone] Validation OK - got \(projects.count) projects")

        authService.saveServerURL(url)
        authService.saveToken(loginResponse.token)
        isAuthenticated = true
    }

    @MainActor
    func logout() async {
        print("[mDone] logout() called")
        authService.clearAll()
        await APIClient.shared.clearCredentials()
        tasks = []
        projects = []
        labels = []
        notifications = []
        isAuthenticated = false
    }

    @MainActor
    func refreshAll() async {
        print("[mDone] refreshAll() called")
        isLoading = true
        defer { isLoading = false }

        do {
            async let fetchedTasks = taskService.fetchAllTasks(perPage: 200)
            async let fetchedProjects = projectService.fetchProjects()

            tasks = try await fetchedTasks
            print("[mDone] refreshAll: got \(tasks.count) tasks")
            projects = try await fetchedProjects
            print("[mDone] refreshAll: got \(projects.count) projects")

            let labelsResult: [VLabel] = try await APIClient.shared.fetch(Endpoint.labels())
            labels = labelsResult
            print("[mDone] refreshAll: got \(labels.count) labels")

            let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
            if notificationsEnabled {
                await notificationService.scheduleReminders(for: tasks)
            }

            errorMessage = nil
            print("[mDone] refreshAll: SUCCESS")
        } catch let error as NetworkError {
            print("[mDone] refreshAll: NetworkError: \(error)")
            if case .unauthorized = error {
                print("[mDone] refreshAll: got .unauthorized, calling logout()")
                await logout()
            }
            errorMessage = error.errorDescription
        } catch {
            print("[mDone] refreshAll: other error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func searchTasks(query: String) async {
        guard !query.isEmpty else {
            await refreshAll()
            return
        }

        do {
            let results: [VTask] = try await APIClient.shared.fetch(
                Endpoint.allTasks(perPage: 200, search: query)
            )
            tasks = results
            errorMessage = nil
        } catch let error as NetworkError {
            if case .unauthorized = error {
                await logout()
            }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func applyAdvancedFilter(_ filterString: String?) async {
        advancedFilterString = filterString

        do {
            let results: [VTask] = try await APIClient.shared.fetch(
                Endpoint.allTasks(perPage: 200, filter: filterString)
            )
            tasks = results
            errorMessage = nil
        } catch let error as NetworkError {
            if case .unauthorized = error {
                await logout()
            }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func toggleTaskDone(_ task: VTask) async {
        do {
            let updated = try await taskService.toggleDone(task: task)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            if updated.done {
                onTaskCompleted?(updated.id)
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createTask(title: String, projectId: Int64, dueDate: Date? = nil, priority: Int64 = 0) async {
        let request = TaskCreateRequest(title: title, dueDate: dueDate, priority: priority)
        do {
            let newTask = try await taskService.createTask(projectId: projectId, request: request)
            tasks.append(newTask)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func updateTask(id: Int64, request: TaskUpdateRequest) async {
        do {
            let updated = try await taskService.updateTask(id: id, request: request)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func deleteTask(_ task: VTask) async {
        do {
            let taskId = task.id
            try await taskService.deleteTask(id: taskId)
            tasks.removeAll { $0.id == taskId }
            onTaskDeleted?(taskId)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasksForProject(_ projectId: Int64) -> [VTask] {
        // Use cached view-specific tasks if available (has correct positions)
        if let cached = projectTaskCache[projectId] {
            return cached.filter { !$0.done }
        }
        return tasks.filter { $0.projectId == projectId && !$0.done }
    }

    /// Fetches tasks for a specific project via the view endpoint, which returns correct positions.
    @MainActor
    func fetchProjectTasks(project: Project) async {
        guard let viewId = project.listViewId else { return }
        do {
            let viewTasks: [VTask] = try await taskService.fetchProjectTasks(
                projectId: project.id, viewId: viewId
            )
            // Store in cache — these have correct per-view positions
            projectTaskCache[project.id] = viewTasks
            // Also update the global task list with any new tasks
            for viewTask in viewTasks {
                if let index = tasks.firstIndex(where: { $0.id == viewTask.id }) {
                    tasks[index] = viewTask
                } else {
                    tasks.append(viewTask)
                }
            }
        } catch {
            print("[mDone] fetchProjectTasks error: \(error)")
        }
    }

    func tasksForDate(_ date: Date) -> [VTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard let dueDate = task.effectiveDueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: date)
        }
    }

    // MARK: - Notifications

    @MainActor
    func fetchNotifications() async {
        do {
            let result: [VNotification] = try await APIClient.shared.fetch(Endpoint.notifications())
            notifications = result
        } catch {
            print("[mDone] fetchNotifications error: \(error)")
        }
    }

    @MainActor
    func markNotificationRead(_ id: Int64) async {
        do {
            // Send empty body to mark as read
            struct EmptyBody: Encodable {}
            let _: VNotification = try await APIClient.shared.send(Endpoint.markNotificationRead(id: id), body: EmptyBody())
            if let index = notifications.firstIndex(where: { $0.id == id }) {
                notifications[index].read = true
                notifications[index].readAt = Date()
            }
        } catch {
            print("[mDone] markNotificationRead error: \(error)")
        }
    }

    @MainActor
    func markAllNotificationsRead() async {
        do {
            struct EmptyBody: Encodable {}
            try await APIClient.shared.sendExpectingEmpty(Endpoint.markAllNotificationsRead, body: EmptyBody())
            for index in notifications.indices {
                notifications[index].read = true
                notifications[index].readAt = Date()
            }
        } catch {
            print("[mDone] markAllNotificationsRead error: \(error)")
        }
    }

    // MARK: - Task Reordering

    func listViewId(for task: VTask) -> Int64 {
        let project = projects.first { $0.id == task.projectId }
        return project?.listViewId ?? 0
    }

    @MainActor
    func moveTask(_ task: VTask, toPosition position: Double, viewId: Int64 = 0) async {
        let resolvedViewId = viewId > 0 ? viewId : listViewId(for: task)
        guard resolvedViewId > 0 else { return }
        do {
            try await taskService.updatePosition(taskId: task.id, position: position, viewId: resolvedViewId)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].position = position
            }
            // Update cached project task order
            if var cached = projectTaskCache[task.projectId] {
                if let cacheIndex = cached.firstIndex(where: { $0.id == task.id }) {
                    cached[cacheIndex].position = position
                }
                projectTaskCache[task.projectId] = cached.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func datesWithTasks(in month: Date) -> [Date: [VTask]] {
        let calendar = Calendar.current
        guard calendar.range(of: .day, in: .month, for: month) != nil else { return [:] }
        var result: [Date: [VTask]] = [:]

        for task in tasks {
            guard let dueDate = task.effectiveDueDate else { continue }
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { continue }

            if dueDate >= monthStart, dueDate < monthEnd {
                let dayStart = calendar.startOfDay(for: dueDate)
                result[dayStart, default: []].append(task)
            }
        }
        return result
    }
}
