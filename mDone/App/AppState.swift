import EventKit
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif
import WidgetKit

@Observable
final class AppState {
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    var activeError: NetworkError?

    var tasks: [VTask] = []
    var projects: [Project] = []
    var archivedProjects: [Project] = []
    var labels: [VLabel] = []
    var notifications: [VNotification] = []
    var selectedProject: Project?

    var searchQuery: String = ""
    var activeFilter: TaskFilter?
    var advancedFilterString: String?
    var pendingOperationsCount: Int = 0
    var isRetrying: Bool = false
    var quickAddTrigger: UUID?

    // Calendar integration
    var calendarEvents: [CalendarEvent] = []
    var calendarAccessGranted: Bool = false
    private let calendarService = CalendarService()
    private(set) var calendarFilterToken = UUID()

    var onTaskCompleted: ((Int64) -> Void)?
    var onTaskDeleted: ((Int64) -> Void)?

    private(set) var undoableCompletion: VTask?

    var canUndoLastCompletion: Bool {
        undoableCompletion != nil
    }

    var undoableCompletionTitle: String? {
        undoableCompletion?.title
    }

    var projectTaskCache: [Int64: [VTask]] = [:]

    var unreadNotificationCount: Int {
        notifications.filter { $0.read != true }.count
    }

    init(
        taskService: TaskService = TaskService(),
        projectService: ProjectService = ProjectService(),
        labelService: LabelService = LabelService()
    ) {
        self.taskService = taskService
        self.projectService = projectService
        self.labelService = labelService
    }

    private let taskService: TaskService
    private let projectService: ProjectService
    private let labelService: LabelService
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared

    private var syncService: SyncService?
    private var networkMonitor: NetworkMonitor?
    private var wasDisconnected: Bool = false
    private var temporaryIdCounter: Int64 = 0

    var isOffline: Bool {
        !(networkMonitor?.isConnected ?? true)
    }

    @MainActor
    func updateRetryState() async {
        isRetrying = await APIClient.shared.isRetrying
    }

    private var handlersRegistered: Bool = false

    @MainActor
    func registerAPIClientHandlers() async {
        guard !handlersRegistered else { return }
        await APIClient.shared.setOnTokensUpdated { token, refreshToken in
            AuthService.shared.saveToken(token)
            if let refreshToken {
                AuthService.shared.saveRefreshToken(refreshToken)
            }
        }
        await APIClient.shared.setOnSessionExpired { [weak self] in
            Task { @MainActor [weak self] in
                await self?.expireSession()
            }
        }
        handlersRegistered = true
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
        pendingOperationsCount = (syncService?.pendingOperationCount()) ?? 0
    }

    // MARK: - Task Identity Resolution (El Escudo)

    /// Traduce un ID falso (negativo) al ID real de la base de datos
    private func realId(from id: Int64) -> Int64 {
        return id < 0 ? (abs(id) / 10000) : id
    }

    /// Devuelve la tarea original real, incluso si le pasas un clon proyectado
    private func resolveRealTask(from task: VTask) -> VTask {
        guard task.id < 0 else { return task }
        let actualId = realId(from: task.id)
        return tasks.first(where: { $0.id == actualId }) ?? task
    }

    // MARK: - Proyecciones

    private func projectedTasks(through endDate: Date) -> [VTask] {
        var result = tasks
        for task in tasks where !task.done && task.isRepeating {
            let futureDates = task.projectedOccurrences(through: endDate)
            for (index, date) in futureDates.enumerated() {
                var virtualTask = task
                virtualTask.dueDate = date
                // HACK VISUAL: Generamos un ID falso y negativo para que SwiftUI
                let fakeId = -((task.id * 10000) + Int64(index + 1))
                
                virtualTask = VTask(
                    id: fakeId, title: task.title, description: task.description,
                    done: task.done, doneAt: task.doneAt, dueDate: date,
                    startDate: task.startDate, endDate: task.endDate, priority: task.priority,
                    projectId: task.projectId, hexColor: task.hexColor, percentDone: task.percentDone,
                    uid: task.uid, position: task.position, isFavorite: task.isFavorite,
                    repeatAfter: task.repeatAfter, repeatMode: task.repeatMode, identifier: task.identifier,
                    index: task.index, reminders: task.reminders, assignees: task.assignees,
                    labels: task.labels, createdBy: task.createdBy, created: task.created,
                    updated: task.updated, bucketId: task.bucketId, coverImageAttachmentId: task.coverImageAttachmentId
                )
                result.append(virtualTask)
            }
        }
        return result
    }

    var overdueTasks: [VTask] {
        tasks.filter { $0.isOverdue && !$0.isDueToday }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var todayTasks: [VTask] {
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        return projectedTasks(through: endOfDay)
            .filter(\.isDueToday)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var calmModeTodayTasks: [VTask] {
        overdueTasks + todayTasks
    }

    var tomorrowTasks: [VTask] {
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return projectedTasks(through: endOfTomorrow)
            .filter(\.isDueTomorrow)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var thisWeekTasks: [VTask] {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return projectedTasks(through: weekEnd)
            .filter { $0.isDueThisWeek && !$0.isDueToday && !$0.isDueTomorrow }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var upcomingTasks: [VTask] {
        let threeMonths = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        return projectedTasks(through: threeMonths)
            .filter {
                guard let dueDate = $0.effectiveDueDate, !$0.done else { return false }
                let calendar = Calendar.current
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date()))
                else { return false }
                return dueDate > weekEnd
            }
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

    // MARK: - Current (long-running) tasks

    static let currentLabelTitle = "Current"

    private static let currentLabelIdKey = "currentLabelId"

    private var storedCurrentLabelId: Int64? {
        get { (UserDefaults.standard.object(forKey: Self.currentLabelIdKey) as? NSNumber)?.int64Value }
        set {
            if let newValue {
                UserDefaults.standard.set(NSNumber(value: newValue), forKey: Self.currentLabelIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentLabelIdKey)
            }
        }
    }

    var currentLabel: VLabel? {
        if let id = storedCurrentLabelId, let match = labels.first(where: { $0.id == id }) {
            return match
        }
        return labels.first { $0.title.caseInsensitiveCompare(Self.currentLabelTitle) == .orderedSame }
    }

    func isCurrent(_ task: VTask) -> Bool {
        guard let currentLabel else { return false }
        return task.labels?.contains { $0.id == currentLabel.id } ?? false
    }

    var currentTasks: [VTask] {
        guard let currentLabel else { return [] }
        return tasks
            .filter { !$0.done && ($0.labels?.contains { $0.id == currentLabel.id } ?? false) }
            .sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    func checkAuth() async {
        await registerAPIClientHandlers()
        let authenticated = authService.isAuthenticated()
        if authenticated {
            await configureAPIClient()
            if let serverURL = authService.getServerURL(),
               let token = authService.getToken()
            {
                SharedKeys.sharedDefaults.set(serverURL, forKey: SharedKeys.serverURLKey)
                SharedTokenStore.save(token)
            }
        }
        isAuthenticated = authenticated
    }

    func configureAPIClient() async {
        guard let serverURL = authService.getServerURL(),
              let token = authService.getToken() else { return }
        await APIClient.shared.configure(
            serverURL: serverURL,
            token: token,
            refreshToken: authService.getRefreshToken()
        )
    }

    @MainActor
    func login(serverURL: String, token: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await registerAPIClientHandlers()
        await APIClient.shared.configure(serverURL: serverURL, token: token)

        _ = try await APIClient.shared.fetch(Endpoint.projects()) as [Project]

        authService.saveServerURL(serverURL)
        authService.saveToken(token)
        isAuthenticated = true
    }

    @MainActor
    func loginWithCredentials(serverURL: String, username: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await registerAPIClientHandlers()
        let url = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        await APIClient.shared.configure(serverURL: url, token: "")

        let loginRequest = LoginRequest(username: username, password: password)
        let loginResponse: LoginResponse = try await APIClient.shared.send(Endpoint.login, body: loginRequest)
        let capturedRefreshToken = await APIClient.shared.currentRefreshToken()

        await APIClient.shared.configure(
            serverURL: url,
            token: loginResponse.token,
            refreshToken: capturedRefreshToken
        )

        _ = try await APIClient.shared.fetch(Endpoint.projects()) as [Project]

        authService.saveServerURL(url)
        authService.saveToken(loginResponse.token)
        if let capturedRefreshToken {
            authService.saveRefreshToken(capturedRefreshToken)
        }
        isAuthenticated = true
    }

    @MainActor
    func logout() async {
        authService.clearAll()
        await tearDownSession()
    }

    @MainActor
    func expireSession() async {
        authService.clearSession()
        await tearDownSession()
    }

    @MainActor
    private func tearDownSession() async {
        await APIClient.shared.clearCredentials()
        tasks = []
        projects = []
        labels = []
        notifications = []
        isAuthenticated = false

        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.widgetDataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    func refreshAll() async {
        isLoading = true

        #if os(iOS)
        let bgTaskId = UIApplication.shared.beginBackgroundTask { }
        #endif

        defer {
            isLoading = false
            isRetrying = false
            #if os(iOS)
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
            #endif
        }

        do {
            async let fetchedTasks = taskService.fetchAllTasks(perPage: 200)
            async let fetchedProjects = projectService.fetchProjects()

            tasks = try await fetchedTasks
            await updateRetryState()
            
            projects = try await fetchedProjects
            await updateRetryState()

            let labelsResult: [VLabel] = try await APIClient.shared.fetch(Endpoint.labels())
            labels = labelsResult

            let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
            if notificationsEnabled {
                await notificationService.scheduleReminders(for: tasks)
            }

            errorMessage = nil
            activeError = nil

            pushWidgetData()
            WidgetCenter.shared.reloadAllTimelines()

            await refreshCalendarEvents()
        } catch let error as NetworkError {
            if case .unauthorized = error {
                await expireSession()
            }
            handleError(error)
        } catch {
            handleError(error)
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
            activeError = nil
        } catch let error as NetworkError {
            if case .unauthorized = error {
                await expireSession()
            }
            handleError(error)
        } catch {
            handleError(error)
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
            activeError = nil
        } catch let error as NetworkError {
            if case .unauthorized = error {
                await expireSession()
            }
            handleError(error)
        } catch {
            handleError(error)
        }
    }

    static func preservingRelations(existing: VTask, response: VTask) -> VTask {
        var result = response
        if result.labels == nil { result.labels = existing.labels }
        return result
    }

    @MainActor
    func toggleTaskDone(_ task: VTask) async {
        let realTask = resolveRealTask(from: task)
        do {
            let response = try await taskService.toggleDone(task: realTask)
            let updated = tasks.first(where: { $0.id == response.id })
                .map { Self.preservingRelations(existing: $0, response: response) } ?? response
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            if updated.done {
                recordCompletionForUndo(realTask)
                onTaskCompleted?(updated.id)
            } else {
                clearUndoIfMatches(id: updated.id)
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    @MainActor
    func undoLastCompletion() async {
        guard let target = undoableCompletion else { return }
        undoableCompletion = nil
        do {
            let request = preservingRepeatData(in: TaskUpdateRequest(done: false), for: target)
            _ = try await taskService.updateTask(id: target.id, request: request)
            var restored = target
            restored.done = false
            if let index = tasks.firstIndex(where: { $0.id == restored.id }) {
                tasks[index] = restored
            } else {
                tasks.append(restored)
            }
            syncService?.updateCachedTask(restored)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if undoableCompletion == nil {
                undoableCompletion = target
            }
            handleError(error)
        }
    }

    func recordCompletionForUndo(_ task: VTask) {
        undoableCompletion = task
    }

    func clearUndoIfMatches(id: Int64) {
        if undoableCompletion?.id == id {
            undoableCompletion = nil
        }
    }

    @MainActor
    @discardableResult
    func createTask(
        title: String,
        projectId: Int64,
        description: String? = nil,
        dueDate: Date? = nil,
        priority: Int64 = 0
    ) async -> VTask? {
        let request = TaskCreateRequest(title: title, description: description, dueDate: dueDate, priority: priority)
        do {
            let newTask = try await taskService.createTask(projectId: projectId, request: request)
            tasks.append(newTask)
            syncService?.updateCachedTask(newTask)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            WidgetCenter.shared.reloadAllTimelines()
            return newTask
        } catch {
            handleError(error)
            return nil
        }
    }

    @MainActor
    func postponeTask(_ task: VTask, byHours hours: Int) async {
        let realTask = resolveRealTask(from: task)
        let baseDate = realTask.effectiveDueDate ?? Date()
        let newDate = Calendar.current.date(byAdding: .hour, value: hours, to: baseDate) ?? baseDate

        let originalDueDate: Date?
        if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
            originalDueDate = tasks[index].dueDate
            tasks[index].dueDate = newDate
        } else {
            originalDueDate = nil
        }

        do {
            let request = preservingRepeatData(in: TaskUpdateRequest(dueDate: newDate), for: realTask)
            let response = try await taskService.updateTask(id: realTask.id, request: request)
            let updated = tasks.first(where: { $0.id == response.id })
                .map { Self.preservingRelations(existing: $0, response: response) } ?? response
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
                tasks[index].dueDate = originalDueDate
            }
            handleError(error)
        }
    }

    @MainActor
    func rescheduleTask(_ task: VTask, to newDate: Date) async {
        let realTask = resolveRealTask(from: task)
        let originalDueDate: Date?
        if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
            originalDueDate = tasks[index].dueDate
            tasks[index].dueDate = newDate
        } else {
            originalDueDate = nil
        }

        do {
            let request = preservingRepeatData(in: TaskUpdateRequest(dueDate: newDate), for: realTask)
            let updated = try await taskService.updateTask(id: realTask.id, request: request)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
                tasks[index].dueDate = originalDueDate
            }
            handleError(error)
        }
    }

    @MainActor
    func updateTask(id: Int64, request: TaskUpdateRequest) async {
        let actualId = realId(from: id)
        let finalRequest: TaskUpdateRequest
        if let existingTask = tasks.first(where: { $0.id == actualId }) {
            finalRequest = preservingRepeatData(in: request, for: existingTask)
        } else {
            finalRequest = request
        }
        do {
            let response = try await taskService.updateTask(id: actualId, request: finalRequest)
            let updated = tasks.first(where: { $0.id == response.id })
                .map { Self.preservingRelations(existing: $0, response: response) } ?? response
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    // MARK: - Current task mutations

    @MainActor
    private func ensureCurrentLabel() async throws -> VLabel {
        if let existing = currentLabel { return existing }
        let created = try await labelService.createLabel(
            LabelCreateRequest(title: Self.currentLabelTitle, hexColor: "1a8cff")
        )
        if !labels.contains(where: { $0.id == created.id }) {
            labels.append(created)
        }
        storedCurrentLabelId = created.id
        return created
    }

    // MARK: - Repeating Task Helper

    private func preservingRepeatData(in request: TaskUpdateRequest, for task: VTask) -> TaskUpdateRequest {
        guard task.isRepeating else { return request }
        var updated = request
        if updated.repeatAfter == nil { updated.repeatAfter = task.repeatAfter }
        if updated.repeatMode == nil { updated.repeatMode = task.repeatMode }
        return updated
    }

    @MainActor
    func toggleCurrent(_ task: VTask) async {
        let realTask = resolveRealTask(from: task)
        let label: VLabel
        do {
            label = try await ensureCurrentLabel()
        } catch {
            handleError(error)
            return
        }

        let wasCurrent = isCurrent(realTask)
        setCurrentLabelLocally(taskId: realTask.id, label: label, present: !wasCurrent)

        do {
            if wasCurrent {
                try await labelService.removeLabel(taskId: realTask.id, labelId: label.id)
            } else {
                try await labelService.addLabel(taskId: realTask.id, labelId: label.id)
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            setCurrentLabelLocally(taskId: realTask.id, label: label, present: wasCurrent)
            handleError(error)
        }
    }

    @MainActor
    private func setCurrentLabelLocally(taskId: Int64, label: VLabel, present: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var labelList = tasks[index].labels ?? []
        if present {
            if !labelList.contains(where: { $0.id == label.id }) {
                labelList.append(label)
            }
        } else {
            labelList.removeAll { $0.id == label.id }
        }
        tasks[index].labels = labelList
        tasks[index].updated = Date()
        syncService?.updateCachedTask(tasks[index])
    }

    @MainActor
    func setProgress(_ task: VTask, percent: Double) async {
        let realTask = resolveRealTask(from: task)
        let clamped = min(max(percent, 0), 1)
        let original = tasks.first(where: { $0.id == realTask.id })?.percentDone
        if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
            tasks[index].percentDone = clamped
            tasks[index].updated = Date()
            syncService?.updateCachedTask(tasks[index])
        }
        do {
            let request = preservingRepeatData(in: TaskUpdateRequest(percentDone: clamped), for: realTask)
            _ = try await taskService.updateTask(id: realTask.id, request: request)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
                tasks[index].percentDone = original
            }
            handleError(error)
        }
    }

    @MainActor
    func deleteTask(_ task: VTask) async {
        let actualId = realId(from: task.id)
        do {
            try await taskService.deleteTask(id: actualId)
            tasks.removeAll { $0.id == actualId }
            syncService?.deleteCachedTask(id: actualId)
            onTaskDeleted?(actualId)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    func tasksForProject(_ projectId: Int64) -> [VTask] {
        let projectTasks = tasks.filter { $0.projectId == projectId && !$0.done }
        if let cached = projectTaskCache[projectId] {
            let orderMap = Dictionary(
                cached.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return projectTasks.sorted { a, b in
                (orderMap[a.id] ?? Int.max) < (orderMap[b.id] ?? Int.max)
            }
        }
        return projectTasks
    }

    @MainActor
    func fetchProjectTasks(project: Project) async {
        guard let viewId = project.listViewId else { return }
        do {
            let viewTasks: [VTask] = try await taskService.fetchProjectTasks(
                projectId: project.id, viewId: viewId
            )
            projectTaskCache[project.id] = Self.uniquedById(viewTasks)
            for viewTask in viewTasks {
                if let index = tasks.firstIndex(where: { $0.id == viewTask.id }) {
                    tasks[index] = viewTask
                } else {
                    tasks.append(viewTask)
                }
            }
        } catch {
        }
    }

    static func uniquedById(_ tasks: [VTask]) -> [VTask] {
        var seen = Set<Int64>()
        return tasks.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Project Mutations

    @MainActor
    @discardableResult
    func createProject(
        title: String,
        description: String? = nil,
        hexColor: String? = nil,
        isFavorite: Bool = false
    ) async -> Project? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = ProjectCreateRequest(
            title: trimmed,
            description: description.flatMap { $0.isEmpty ? nil : $0 },
            hexColor: hexColor.flatMap { $0.isEmpty ? nil : $0 },
            isFavorite: isFavorite
        )
        do {
            let newProject = try await projectService.createProject(request)
            projects.append(newProject)
            syncService?.updateCachedProject(newProject)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            WidgetCenter.shared.reloadAllTimelines()
            return newProject
        } catch {
            handleError(error)
            return nil
        }
    }

    @MainActor
    func updateProject(
        _ project: Project,
        title: String,
        description: String,
        hexColor: String,
        isFavorite: Bool
    ) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let request = ProjectUpdateRequest(
            from: project,
            title: trimmed,
            description: description,
            hexColor: hexColor,
            isFavorite: isFavorite
        )
        await performProjectUpdate(id: project.id, request: request)
    }

    @MainActor
    func archiveProject(_ project: Project) async {
        guard project.id > 0 else { return }
        await performProjectUpdate(id: project.id, request: ProjectUpdateRequest(from: project, isArchived: true))
    }

    @MainActor
    func unarchiveProject(_ project: Project) async {
        guard project.id > 0 else { return }
        await performProjectUpdate(id: project.id, request: ProjectUpdateRequest(from: project, isArchived: false))
    }

    @MainActor
    func deleteProject(_ project: Project) async {
        guard project.id > 0 else { return }
        let projectId = project.id
        do {
            try await projectService.deleteProject(id: projectId)
            let removedIds = descendantProjectIds(of: projectId)
            projects.removeAll { removedIds.contains($0.id) }
            archivedProjects.removeAll { removedIds.contains($0.id) }
            tasks.removeAll { removedIds.contains($0.projectId) }
            for id in removedIds {
                projectTaskCache[id] = nil
                syncService?.deleteCachedProject(id: id)
            }
            if let selectedId = selectedProject?.id, removedIds.contains(selectedId) {
                selectedProject = nil
            }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    private func descendantProjectIds(of root: Int64) -> Set<Int64> {
        var ids: Set<Int64> = [root]
        let all = projects + archivedProjects
        var changed = true
        while changed {
            changed = false
            for project in all
                where project.parentProjectId.map({ ids.contains($0) }) == true && !ids.contains(project.id)
            {
                ids.insert(project.id)
                changed = true
            }
        }
        return ids
    }

    @MainActor
    func fetchArchivedProjects() async {
        do {
            let all = try await projectService.fetchProjects(includeArchived: true)
            archivedProjects = all.filter { $0.isArchived == true }
        } catch {
            handleError(error)
        }
    }

    @MainActor
    private func performProjectUpdate(id: Int64, request: ProjectUpdateRequest) async {
        do {
            var updated = try await projectService.updateProject(id: id, request: request)
            updated.isArchived = request.isArchived
            applyUpdatedProject(updated)
            syncService?.updateCachedProject(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    @MainActor
    private func applyUpdatedProject(_ project: Project) {
        if project.isArchived ?? false {
            projects.removeAll { $0.id == project.id }
            if let idx = archivedProjects.firstIndex(where: { $0.id == project.id }) {
                archivedProjects[idx] = project
            } else {
                archivedProjects.append(project)
            }
            if selectedProject?.id == project.id { selectedProject = nil }
        } else {
            archivedProjects.removeAll { $0.id == project.id }
            if let idx = projects.firstIndex(where: { $0.id == project.id }) {
                projects[idx] = project
            } else {
                projects.append(project)
            }
            if selectedProject?.id == project.id { selectedProject = project }
        }
    }

    // MARK: - Calendar Events

    @MainActor
    func requestCalendarAccess() async {
        calendarAccessGranted = await calendarService.requestAccess()
        if calendarAccessGranted {
            await refreshCalendarEvents()
        }
    }

    @MainActor
    func refreshCalendarEvents() async {
        guard calendarAccessGranted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        calendarEvents = await calendarService.fetchEvents(from: start, to: end)
    }

    func calendarEventsForDate(_ date: Date) async -> [CalendarEvent] {
        guard calendarAccessGranted else { return [] }
        return await calendarService.eventsForDate(date)
    }

    func calendarEventsForMonth(_ date: Date) async -> [Date: [CalendarEvent]] {
        guard calendarAccessGranted else { return [:] }
        return await calendarService.eventsForMonth(date)
    }

    func availableCalendars() async -> [CalendarInfo] {
        guard calendarAccessGranted else { return [] }
        return await calendarService.availableCalendars()
    }

    @MainActor
    func calendarSelectionDidChange() async {
        calendarFilterToken = UUID()
        await refreshCalendarEvents()
    }

    var todayCalendarEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return [] }
        return calendarEvents.filter { $0.startDate >= todayStart && $0.startDate < todayEnd }
    }

    func tasksForDate(_ date: Date) -> [VTask] {
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
        let allTasks = projectedTasks(through: endOfDay)
        
        return allTasks.filter { task in
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
        }
    }

    @MainActor
    func markNotificationRead(_ id: Int64) async {
        do {
            struct EmptyBody: Encodable {}
            let _: VNotification = try await APIClient.shared.send(
                Endpoint.markNotificationRead(id: id),
                body: EmptyBody()
            )
            if let index = notifications.firstIndex(where: { $0.id == id }) {
                notifications[index].read = true
                notifications[index].readAt = Date()
            }
        } catch {
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
        }
    }

    // MARK: - Task Reordering

    func listViewId(for task: VTask) -> Int64 {
        let project = projects.first { $0.id == task.projectId }
        return project?.listViewId ?? 0
    }

    @MainActor
    func moveTask(_ task: VTask, toPosition position: Double, viewId: Int64 = 0) async {
        let realTask = resolveRealTask(from: task)
        let resolvedViewId = viewId > 0 ? viewId : listViewId(for: realTask)
        guard resolvedViewId > 0 else { return }
        do {
            try await taskService.updatePosition(taskId: realTask.id, position: position, viewId: resolvedViewId)
            if let index = tasks.firstIndex(where: { $0.id == realTask.id }) {
                tasks[index].position = position
            }
            if var cached = projectTaskCache[realTask.projectId] {
                if let cacheIndex = cached.firstIndex(where: { $0.id == realTask.id }) {
                    cached[cacheIndex].position = position
                }
                projectTaskCache[realTask.projectId] = cached.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            }
        } catch {
            handleError(error)
        }
    }

    func datesWithTasks(in month: Date) -> [Date: [VTask]] {
        let calendar = Calendar.current
        guard calendar.range(of: .day, in: .month, for: month) != nil else { return [:] }
        var result: [Date: [VTask]] = [:]

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }

        let allTasks = projectedTasks(through: monthEnd)

        for task in allTasks {
            guard let dueDate = task.effectiveDueDate else { continue }

            if dueDate >= monthStart, dueDate < monthEnd {
                let dayStart = calendar.startOfDay(for: dueDate)
                result[dayStart, default: []].append(task)
            }
        }
        return result
    }

    // MARK: - Error Handling

    @MainActor
    private func handleError(_ error: Error) {
        let friendlyError = NetworkError.friendly(from: error)
        errorMessage = friendlyError.errorDescription
        activeError = friendlyError
    }

    // MARK: - Widget Data

    private func pushWidgetData() {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let projectLookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })

        func toWidgetTask(_ task: VTask) -> WidgetTask {
            WidgetTask(
                id: task.id,
                title: task.title,
                done: task.done,
                dueDate: task.effectiveDueDate,
                priority: Int(task.priority),
                projectId: task.projectId,
                projectTitle: projectLookup[task.projectId],
                isOverdue: task.isOverdue
            )
        }

        let today = tasks
            .filter { $0.isDueToday && !$0.done }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(10)
            .map(toWidgetTask)

        let upcoming = tasks
            .filter {
                guard let due = $0.effectiveDueDate, !$0.done else { return false }
                return due > endOfDay
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(10)
            .map(toWidgetTask)

        let overdue = tasks
            .filter { $0.isOverdue && !$0.isDueToday }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(10)
            .map(toWidgetTask)

        let widgetData = WidgetData(
            todayTasks: Array(today),
            upcomingTasks: Array(upcoming),
            overdueTasks: Array(overdue),
            lastUpdated: now
        )

        WidgetDataProvider.shared.cacheWidgetData(widgetData)
    }
}
