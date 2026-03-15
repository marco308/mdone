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
    var selectedProject: Project?

    private let taskService = TaskService()
    private let projectService = ProjectService()
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared

    var overdueTasks: [VTask] {
        tasks.filter(\.isOverdue).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
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

    func checkAuth() {
        isAuthenticated = authService.isAuthenticated()
        if isAuthenticated {
            configureAPIClient()
        }
    }

    func configureAPIClient() {
        guard let serverURL = authService.getServerURL(),
              let token = authService.getToken() else { return }
        Task {
            await APIClient.shared.configure(serverURL: serverURL, token: token)
        }
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
    func logout() async {
        print("[mDone] logout() called")
        authService.clearAll()
        await APIClient.shared.clearCredentials()
        tasks = []
        projects = []
        labels = []
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
    func toggleTaskDone(_ task: VTask) async {
        do {
            let updated = try await taskService.toggleDone(task: task)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
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
            try await taskService.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasksForProject(_ projectId: Int64) -> [VTask] {
        tasks.filter { $0.projectId == projectId && !$0.done }
    }

    func tasksForDate(_ date: Date) -> [VTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard let dueDate = task.effectiveDueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: date)
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
