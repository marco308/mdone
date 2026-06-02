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
    /// Archived projects, loaded on demand for the Archived view. Kept separate
    /// from `projects`, which only ever holds active (non-archived) projects.
    var archivedProjects: [Project] = []
    var labels: [VLabel] = []
    var notifications: [VNotification] = []
    var selectedProject: Project?

    var searchQuery: String = ""
    var activeFilter: TaskFilter?
    var advancedFilterString: String?
    var pendingOperationsCount: Int = 0
    var isRetrying: Bool = false

    /// Bumped when the user opens the app via the widget's "+ Add Task" shortcut
    /// or the mdone://create URL. Observed by MainTabView (switch to Inbox) and
    /// QuickAddBar (focus the text field).
    var quickAddTrigger: UUID?

    // Calendar integration
    var calendarEvents: [CalendarEvent] = []
    var calendarAccessGranted: Bool = false
    private let calendarService = CalendarService()

    /// Changes whenever the visible-calendar selection changes. Calendar
    /// views key their event fetch on this so toggling a calendar refreshes
    /// the grid and day list immediately, not just the Today view.
    private(set) var calendarFilterToken = UUID()

    var onTaskCompleted: ((Int64) -> Void)?
    var onTaskDeleted: ((Int64) -> Void)?

    /// The most recently completed task, eligible for shake-to-undo on iPhone.
    /// Holds the task as it was *before* completion so undo can restore it.
    /// Replaced when a newer task is completed, and cleared once undone or if
    /// the same task is un-completed by other means.
    private(set) var undoableCompletion: VTask?

    var canUndoLastCompletion: Bool {
        undoableCompletion != nil
    }

    var undoableCompletionTitle: String? {
        undoableCompletion?.title
    }

    /// Per-project ordered task lists fetched from the view endpoint (preserves positions).
    var projectTaskCache: [Int64: [VTask]] = [:]

    var unreadNotificationCount: Int {
        notifications.filter { $0.read != true }.count
    }

    /// `taskService` is injectable so tests can drive the network paths
    /// (e.g. `undoLastCompletion`) through a mocked `APIClient`.
    init(taskService: TaskService = TaskService(), projectService: ProjectService = ProjectService()) {
        self.taskService = taskService
        self.projectService = projectService
    }

    private let taskService: TaskService
    private let projectService: ProjectService
    private let authService = AuthService.shared
    private let notificationService = NotificationService.shared

    private var syncService: SyncService?
    private var networkMonitor: NetworkMonitor?
    private var wasDisconnected: Bool = false
    private var temporaryIdCounter: Int64 = 0

    var isOffline: Bool {
        !(networkMonitor?.isConnected ?? true)
    }

    /// Polls the APIClient's retry state and updates the published `isRetrying` property.
    @MainActor
    func updateRetryState() async {
        isRetrying = await APIClient.shared.isRetrying
    }

    /// Tracks whether `registerAPIClientHandlers()` has installed the
    /// refreshed-tokens and session-expired callbacks on `APIClient.shared`.
    /// Installation is idempotent but we skip the actor hop after the first
    /// successful pass.
    private var handlersRegistered: Bool = false

    /// Installs the APIClient → AppState callbacks. Must be awaited **before**
    /// any network traffic so refreshed tokens get persisted and unrecoverable
    /// 401s push the user back to the login screen instead of hanging on a
    /// stale session.
    ///
    /// Previously this lived in `init()` inside an unstructured `Task`, which
    /// raced the first network call. Every public entry point that touches the
    /// network (`checkAuth`, `login`, `loginWithCredentials`) now awaits this
    /// up-front instead.
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
        pendingOperationsCount = (try? syncService?.pendingOperationCount()) ?? 0
    }

    var overdueTasks: [VTask] {
        tasks.filter { $0.isOverdue && !$0.isDueToday }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var todayTasks: [VTask] {
        tasks.filter(\.isDueToday).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var tomorrowTasks: [VTask] {
        tasks.filter(\.isDueTomorrow).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var thisWeekTasks: [VTask] {
        tasks.filter { $0.isDueThisWeek && !$0.isDueToday && !$0.isDueTomorrow }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var upcomingTasks: [VTask] {
        tasks.filter {
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

    func checkAuth() async {
        await registerAPIClientHandlers()
        let authenticated = authService.isAuthenticated()
        if authenticated {
            await configureAPIClient()
            // Sync credentials to shared App Group UserDefaults so widgets can access them
            if let serverURL = authService.getServerURL(),
               let token = authService.getToken()
            {
                SharedKeys.sharedDefaults.set(serverURL, forKey: SharedKeys.serverURLKey)
                SharedKeys.sharedDefaults.set(token, forKey: SharedKeys.apiTokenKey)
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
        #if DEBUG
        print("[mDone] login() called with serverURL: \(serverURL)")
        #endif
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await registerAPIClientHandlers()
        await APIClient.shared.configure(serverURL: serverURL, token: token)

        // Validate by fetching projects — works with both JWT and API tokens
        #if DEBUG
        print("[mDone] Fetching projects to validate...")
        #endif
        let projects: [Project] = try await APIClient.shared.fetch(Endpoint.projects())
        #if DEBUG
        print("[mDone] Validation OK - got \(projects.count) projects")
        #endif

        authService.saveServerURL(serverURL)
        authService.saveToken(token)
        #if DEBUG
        print("[mDone] Credentials saved, setting isAuthenticated = true")
        #endif
        isAuthenticated = true
    }

    @MainActor
    func loginWithCredentials(serverURL: String, username: String, password: String) async throws {
        #if DEBUG
        print("[mDone] loginWithCredentials() called")
        #endif
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await registerAPIClientHandlers()
        let url = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        await APIClient.shared.configure(serverURL: url, token: "")

        // Get JWT token via login endpoint. The Vikunja 2.0+ `Set-Cookie:
        // vikunja_refresh_token=…` header is captured inside APIClient as part
        // of the response — we read it back after this call to persist it.
        let loginRequest = LoginRequest(username: username, password: password)
        let loginResponse: LoginResponse = try await APIClient.shared.send(Endpoint.login, body: loginRequest)
        let capturedRefreshToken = await APIClient.shared.currentRefreshToken()

        // Configure with the JWT token + refresh cookie so subsequent requests
        // (and the 401 retry path) have everything they need.
        await APIClient.shared.configure(
            serverURL: url,
            token: loginResponse.token,
            refreshToken: capturedRefreshToken
        )

        // Validate
        let projects: [Project] = try await APIClient.shared.fetch(Endpoint.projects())
        #if DEBUG
        print("[mDone] Validation OK - got \(projects.count) projects")
        #endif

        authService.saveServerURL(url)
        authService.saveToken(loginResponse.token)
        if let capturedRefreshToken {
            authService.saveRefreshToken(capturedRefreshToken)
        }
        isAuthenticated = true
    }

    @MainActor
    func logout() async {
        #if DEBUG
        print("[mDone] logout() called")
        #endif
        authService.clearAll()
        await tearDownSession()
    }

    /// Called when the server stops accepting our credentials (refresh failed,
    /// API token revoked, etc.). Drops the session creds but keeps the server
    /// URL so the user only has to re-enter their password on the next launch.
    /// Issue #80: previously a stale JWT triggered a full `clearAll()`, which
    /// wiped the server URL too.
    @MainActor
    func expireSession() async {
        #if DEBUG
        print("[mDone] expireSession() called")
        #endif
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

        // Clear cached widget data and refresh widgets
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.widgetDataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    func refreshAll() async {
        #if DEBUG
        print("[mDone] refreshAll() called")
        #endif
        isLoading = true

        #if os(iOS)
        // Request background execution time so in-flight network requests
        // can finish if the user switches away mid-refresh (issue #49).
        let bgTaskId = UIApplication.shared.beginBackgroundTask {
            // Expiration handler — nothing to clean up, the requests will
            // be cancelled by the system after this returns.
        }
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
            #if DEBUG
            print("[mDone] refreshAll: got \(tasks.count) tasks")
            #endif
            projects = try await fetchedProjects
            await updateRetryState()
            #if DEBUG
            print("[mDone] refreshAll: got \(projects.count) projects")
            #endif

            let labelsResult: [VLabel] = try await APIClient.shared.fetch(Endpoint.labels())
            labels = labelsResult
            #if DEBUG
            print("[mDone] refreshAll: got \(labels.count) labels")
            #endif

            let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
            if notificationsEnabled {
                await notificationService.scheduleReminders(for: tasks)
            }

            errorMessage = nil
            activeError = nil
            #if DEBUG
            print("[mDone] refreshAll: SUCCESS")
            #endif

            pushWidgetData()
            WidgetCenter.shared.reloadAllTimelines()

            await refreshCalendarEvents()
        } catch let error as NetworkError {
            #if DEBUG
            print("[mDone] refreshAll: NetworkError: \(error)")
            #endif
            if case .unauthorized = error {
                #if DEBUG
                print("[mDone] refreshAll: got .unauthorized, expiring session")
                #endif
                await expireSession()
            }
            handleError(error)
        } catch {
            #if DEBUG
            print("[mDone] refreshAll: other error: \(error)")
            #endif
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

    @MainActor
    func toggleTaskDone(_ task: VTask) async {
        do {
            let updated = try await taskService.toggleDone(task: task)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            if updated.done {
                recordCompletionForUndo(task)
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

    /// Restores the most recently completed task to its incomplete state.
    /// Invoked by the iPhone shake-to-undo prompt. No-op when nothing is
    /// pending undo. On failure the undo target is kept so the user can retry.
    @MainActor
    func undoLastCompletion() async {
        guard let target = undoableCompletion else { return }
        undoableCompletion = nil
        do {
            _ = try await taskService.updateTask(id: target.id, request: TaskUpdateRequest(done: false))
            // Restore the task to its exact pre-completion state. We rebuild from
            // the stored snapshot rather than the update response because the
            // response can omit fields like the due date, which would land the
            // task in the wrong Inbox section (e.g. "No Date" instead of "Today").
            // The completed task may also have been dropped from `tasks` by a
            // refresh (the all-tasks fetch returns only undone tasks), so re-insert
            // it when it's no longer present rather than silently doing nothing.
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
            // Only restore the old target if no newer completion was recorded
            // while this request was in flight — otherwise we'd clobber the more
            // recent undo target and break "undo the most recent completion".
            if undoableCompletion == nil {
                undoableCompletion = target
            }
            handleError(error)
        }
    }

    /// Records `task` (in its pre-completion state) as the pending shake-to-undo
    /// target. Exposed for testing the tracking logic without a network round-trip.
    func recordCompletionForUndo(_ task: VTask) {
        undoableCompletion = task
    }

    func clearUndoIfMatches(id: Int64) {
        if undoableCompletion?.id == id {
            undoableCompletion = nil
        }
    }

    /// Creates a task and returns it on success (or `nil` on failure).
    /// `@discardableResult` so existing call sites that don't need the new id
    /// stay unchanged.
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
        let baseDate = task.effectiveDueDate ?? Date()
        let newDate = Calendar.current.date(byAdding: .hour, value: hours, to: baseDate) ?? baseDate

        let originalDueDate: Date?
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            originalDueDate = tasks[index].dueDate
            tasks[index].dueDate = newDate
        } else {
            originalDueDate = nil
        }

        do {
            let updated = try await taskService.updateTask(id: task.id, request: TaskUpdateRequest(dueDate: newDate))
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].dueDate = originalDueDate
            }
            handleError(error)
        }
    }

    @MainActor
    func updateTask(id: Int64, request: TaskUpdateRequest) async {
        do {
            let updated = try await taskService.updateTask(id: id, request: request)
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            syncService?.updateCachedTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    @MainActor
    func deleteTask(_ task: VTask) async {
        do {
            let taskId = task.id
            try await taskService.deleteTask(id: taskId)
            tasks.removeAll { $0.id == taskId }
            syncService?.deleteCachedTask(id: taskId)
            onTaskDeleted?(taskId)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    func tasksForProject(_ projectId: Int64) -> [VTask] {
        // Always read latest task data from the tasks array (source of truth).
        // Use the cache only for position ordering.
        let projectTasks = tasks.filter { $0.projectId == projectId && !$0.done }
        if let cached = projectTaskCache[projectId] {
            // Keep the earliest index when an id appears twice; Vikunja can return
            // duplicate task rows from the view endpoint if task_positions has
            // duplicate (task_id, project_view_id) rows.
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

    /// Fetches tasks for a specific project via the view endpoint, which returns correct positions.
    @MainActor
    func fetchProjectTasks(project: Project) async {
        guard let viewId = project.listViewId else { return }
        do {
            let viewTasks: [VTask] = try await taskService.fetchProjectTasks(
                projectId: project.id, viewId: viewId
            )
            // Store in cache — these have correct per-view positions.
            // Dedupe by id: Vikunja's view-tasks endpoint can return the same task
            // more than once when task_positions has duplicate rows for the view.
            projectTaskCache[project.id] = Self.uniquedById(viewTasks)
            // Also update the global task list with any new tasks
            for viewTask in viewTasks {
                if let index = tasks.firstIndex(where: { $0.id == viewTask.id }) {
                    tasks[index] = viewTask
                } else {
                    tasks.append(viewTask)
                }
            }
        } catch {
            #if DEBUG
            print("[mDone] fetchProjectTasks error: \(error)")
            #endif
        }
    }

    /// Returns the input with duplicate `id`s removed, preserving the first occurrence.
    static func uniquedById(_ tasks: [VTask]) -> [VTask] {
        var seen = Set<Int64>()
        return tasks.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Project Mutations

    /// Creates a project and returns it on success (or `nil` on failure).
    /// Empty description/colour are sent as `nil` so Vikunja stores them empty.
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

    /// Applies edits from the edit sheet. Sends the project's full field set so no
    /// column is accidentally cleared server-side.
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

    /// Archives a project (reversible). It leaves the active list and joins `archivedProjects`.
    @MainActor
    func archiveProject(_ project: Project) async {
        guard project.id > 0 else { return }
        await performProjectUpdate(id: project.id, request: ProjectUpdateRequest(from: project, isArchived: true))
    }

    /// Unarchives a project, returning it to the active list.
    @MainActor
    func unarchiveProject(_ project: Project) async {
        guard project.id > 0 else { return }
        await performProjectUpdate(id: project.id, request: ProjectUpdateRequest(from: project, isArchived: false))
    }

    /// Permanently deletes a project. Vikunja cascades this server-side to every task
    /// and descendant project — it cannot be undone. Cleans up all local state that
    /// referenced the project so no ghost rows or stale selection remain.
    @MainActor
    func deleteProject(_ project: Project) async {
        guard project.id > 0 else { return } // never delete pseudo-projects (e.g. Favorites, id -1)
        let projectId = project.id
        do {
            try await projectService.deleteProject(id: projectId)
            // Vikunja cascades the delete to descendant sub-projects and all their
            // tasks; mirror that locally so no orphaned rows linger until the next
            // full refresh.
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

    /// Returns `root` plus the IDs of every known descendant project (transitive
    /// closure over `parentProjectId`), matching Vikunja's recursive delete cascade.
    private func descendantProjectIds(of root: Int64) -> Set<Int64> {
        var ids: Set<Int64> = [root]
        let all = projects + archivedProjects
        var changed = true
        while changed {
            changed = false
            for project in all where project.parentProjectId.map({ ids.contains($0) }) == true && !ids.contains(project.id) {
                ids.insert(project.id)
                changed = true
            }
        }
        return ids
    }

    /// Loads archived projects for the Archived view. Vikunja's include-archived fetch
    /// returns active **and** archived projects, so we keep only the archived ones.
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
            // Trust our intended archived state for list placement, in case the
            // server response omits `is_archived`.
            updated.isArchived = request.isArchived
            applyUpdatedProject(updated)
            syncService?.updateCachedProject(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handleError(error)
        }
    }

    /// Routes an updated project into `projects` or `archivedProjects` based on its
    /// archived state, removing it from the other list. Edits to an active project keep
    /// their position (in-place replace); unarchived projects append until next refresh.
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

    /// Event calendars available for the "Show in mDone" selection screen.
    func availableCalendars() async -> [CalendarInfo] {
        guard calendarAccessGranted else { return [] }
        return await calendarService.availableCalendars()
    }

    /// Call after the user changes which calendars are visible. Bumps the
    /// token so calendar views re-query, and refreshes the Today window.
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
            #if DEBUG
            print("[mDone] fetchNotifications error: \(error)")
            #endif
        }
    }

    @MainActor
    func markNotificationRead(_ id: Int64) async {
        do {
            // Send empty body to mark as read
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
            #if DEBUG
            print("[mDone] markNotificationRead error: \(error)")
            #endif
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
            #if DEBUG
            print("[mDone] markAllNotificationsRead error: \(error)")
            #endif
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
            handleError(error)
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

    // MARK: - Error Handling

    @MainActor
    private func handleError(_ error: Error) {
        let friendlyError = NetworkError.friendly(from: error)
        errorMessage = friendlyError.errorDescription
        activeError = friendlyError
    }

    // MARK: - Widget Data

    /// Serializes current task data as WidgetData to the shared App Group UserDefaults
    /// so widgets have instant access without needing to make API calls.
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
