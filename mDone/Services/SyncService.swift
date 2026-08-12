import Foundation
import OSLog
import SwiftData

actor SyncService {
    private let taskService: TaskService
    private let projectService: ProjectService
    private let modelContainer: ModelContainer
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.mdone", category: "SyncService")

    private static let maxRetries = 3

    init(
        taskService: TaskService,
        projectService: ProjectService,
        modelContainer: ModelContainer,
        apiClient: APIClient = .shared
    ) {
        self.taskService = taskService
        self.projectService = projectService
        self.modelContainer = modelContainer
        self.apiClient = apiClient
    }

    // MARK: - Pending Operations Queue

    @MainActor
    func queueOperation(endpoint: Endpoint, body: some Encodable) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try? encoder.encode(body)
        insertPendingOperation(endpoint: endpoint, bodyData: bodyData)
    }

    @MainActor
    func queueOperation(endpoint: Endpoint) {
        insertPendingOperation(endpoint: endpoint, bodyData: nil)
    }

    // MARK: - Offline task edits (issue #146)

    private static func editEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func editDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Queues an edit to an existing task for replay when the connection comes
    /// back. Repeat edits of the same task are folded into the one pending
    /// operation, so ticking a task on and off while offline settles on its
    /// final state rather than replaying every intermediate step.
    @MainActor
    func queueTaskEdit(taskId: Int64, edit: QueuedTaskEdit) {
        let context = modelContainer.mainContext

        if let existing = pendingEdit(for: taskId, in: context) {
            let stored = existing.bodyData
                .flatMap { try? SyncService.editDecoder().decode(QueuedTaskEdit.self, from: $0) }
            let combined = stored?.coalesced(with: edit) ?? edit
            existing.bodyData = try? SyncService.editEncoder().encode(combined)
            // A coalesced edit is a fresh attempt, not a continuation of a
            // failed one, so give it its retries back.
            existing.retryCount = 0
            existing.failed = false
            existing.failureReason = nil
            try? context.save()
            logger.info("Coalesced offline edit for task \(taskId)")
            return
        }

        let operation = PendingOperation(
            endpointPath: Endpoint.updateTask(id: taskId).path,
            method: HTTPMethod.POST.rawValue,
            bodyData: try? SyncService.editEncoder().encode(edit),
            kind: .taskEdit,
            taskId: taskId
        )
        context.insert(operation)
        try? context.save()
        logger.info("Queued offline edit for task \(taskId)")
    }

    /// Queues a delete. Any pending edits for the same task are dropped: editing
    /// then deleting offline should not replay an update against a task that is
    /// about to stop existing.
    @MainActor
    func queueTaskDelete(taskId: Int64) {
        let context = modelContainer.mainContext

        for operation in pendingOperations(for: taskId, in: context) {
            context.delete(operation)
        }

        let operation = PendingOperation(
            endpointPath: Endpoint.deleteTask(id: taskId).path,
            method: HTTPMethod.DELETE.rawValue,
            kind: .taskDelete,
            taskId: taskId
        )
        context.insert(operation)
        try? context.save()
        logger.info("Queued offline delete for task \(taskId)")
    }

    @MainActor
    private func pendingOperations(for taskId: Int64, in context: ModelContext) -> [PendingOperation] {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.taskId == taskId }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private func pendingEdit(for taskId: Int64, in context: ModelContext) -> PendingOperation? {
        pendingOperations(for: taskId, in: context)
            .first { $0.operationKind == .taskEdit }
    }

    /// Ids of tasks with changes still waiting to sync, so the UI can mark those
    /// rows rather than leaving the user guessing which edits landed.
    @MainActor
    func pendingTaskIds() -> Set<Int64> {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { !$0.failed }
        )
        let operations = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return Set(operations.compactMap(\.taskId))
    }

    /// Changes that exhausted their retries and were abandoned, for reporting.
    @MainActor
    func failedOperations() -> [PendingOperation] {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.failed },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    /// Clears abandoned operations once the user has been told about them.
    @MainActor
    func discardFailedOperations() {
        let context = modelContainer.mainContext
        for operation in failedOperations() {
            context.delete(operation)
        }
        try? context.save()
    }

    @MainActor
    private func insertPendingOperation(endpoint: Endpoint, bodyData: Data?) {
        let context = modelContainer.mainContext
        let operation = PendingOperation(
            endpointPath: endpoint.path,
            method: endpoint.method.rawValue,
            bodyData: bodyData
        )
        context.insert(operation)
        try? context.save()
        logger.info("Queued pending operation: \(endpoint.method.rawValue) \(endpoint.path)")
    }

    @MainActor
    func processPendingOperations() async {
        let context = modelContainer.mainContext

        var descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { !$0.failed },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 50

        guard let operations = try? context.fetch(descriptor), !operations.isEmpty else {
            logger.info("No pending operations to process")
            return
        }

        logger.info("Processing \(operations.count) pending operations")

        for operation in operations {
            do {
                switch operation.operationKind {
                case .taskEdit:
                    try await replayTaskEdit(operation)
                case .taskDelete, .none:
                    let endpoint = Endpoint(
                        path: operation.endpointPath,
                        method: HTTPMethod(rawValue: operation.method) ?? .GET
                    )
                    if endpoint.method == .DELETE {
                        try await apiClient.delete(endpoint)
                    } else {
                        try await apiClient.sendRawData(endpoint, bodyData: operation.bodyData)
                    }
                }

                context.delete(operation)
                try? context.save()
                logger.info("Successfully processed: \(operation.method) \(operation.endpointPath)")
            } catch NetworkError.unauthorized {
                // Not this operation's fault, and every remaining one will hit
                // the same wall. Leave the queue untouched, without spending a
                // retry, so the changes still go out after the user signs back
                // in rather than being discarded for an expired session.
                logger.error("Sync paused: session expired with \(operations.count) operations still queued")
                return
            } catch let error as NetworkError where Self.isPermanentFailure(error) {
                // Retrying a 404 or a 400 will never succeed: the task was
                // deleted elsewhere, or the server rejected the payload. Abandon
                // it now rather than burning three attempts to reach the same
                // conclusion, and record why so the user can be told.
                operation.failed = true
                operation.failureReason = error.errorDescription
                logger.error("Abandoning \(operation.endpointPath): \(error.localizedDescription)")
                try? context.save()
            } catch {
                operation.retryCount += 1
                logger
                    .error(
                        "Failed operation \(operation.method) \(operation.endpointPath) (attempt \(operation.retryCount)): \(error.localizedDescription)"
                    )

                if operation.retryCount >= SyncService.maxRetries {
                    operation.failed = true
                    operation.failureReason = NetworkError.friendly(from: error).errorDescription
                    logger
                        .error(
                            "Operation marked as failed after \(SyncService.maxRetries) retries: \(operation.method) \(operation.endpointPath)"
                        )
                }

                try? context.save()
            }
        }
    }

    /// Replays an offline edit against the task as it stands on the server *now*.
    ///
    /// The queued body is the user's intent, not a finished request: it holds
    /// only the fields they changed. Reading the task first and merging onto it
    /// means an edit made offline no longer clobbers whatever else changed while
    /// the device was away (issue #146).
    @MainActor
    private func replayTaskEdit(_ operation: PendingOperation) async throws {
        guard let taskId = operation.taskId,
              let bodyData = operation.bodyData,
              let edit = try? SyncService.editDecoder().decode(QueuedTaskEdit.self, from: bodyData)
        else {
            throw NetworkError.decodingError(
                NSError(domain: "SyncService", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Queued edit could not be read back",
                ])
            )
        }

        let fresh = try await taskService.fetchTask(id: taskId)
        let request = edit.request.preservingExistingValues(from: fresh)
        _ = try await taskService.updateTask(id: taskId, request: request)
    }

    /// Failures that no amount of retrying will fix.
    ///
    /// 401 is deliberately excluded and handled separately: an expired session
    /// is a property of the app, not of the queued change, and the change should
    /// survive until the user signs back in.
    private static func isPermanentFailure(_ error: NetworkError) -> Bool {
        switch error {
        case let .serverError(statusCode, _):
            // 404: gone from the server. 4xx generally: the server won't take it.
            (400 ... 499).contains(statusCode) && statusCode != 401
        case .decodingError:
            true
        default:
            false
        }
    }

    @MainActor
    func pendingOperationCount() -> Int {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { !$0.failed }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Cache Writes

    /// Replaces the cached task list with `tasks`: rows that still exist are
    /// updated in place, new ones inserted, and rows the server no longer
    /// returns deleted. Takes an already-fetched list rather than fetching its
    /// own so `AppState.refreshAll()` can persist exactly what it just put on
    /// screen without a second round trip (issue #144).
    @MainActor
    func cacheTasks(_ tasks: [VTask]) throws {
        let context = modelContainer.mainContext
        let existing = try context.fetch(FetchDescriptor<CachedTask>())
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for task in tasks {
            if let cached = existingById[task.id] {
                cached.update(from: task)
            } else {
                context.insert(CachedTask(from: task))
            }
        }

        let fetchedIds = Set(tasks.map(\.id))
        for row in existing where !fetchedIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
    }

    @MainActor
    func cacheProjects(_ projects: [Project]) throws {
        let context = modelContainer.mainContext
        let existing = try context.fetch(FetchDescriptor<CachedProject>())
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for project in projects {
            if let cached = existingById[project.id] {
                cached.update(from: project)
            } else {
                context.insert(CachedProject(from: project))
            }
        }

        let fetchedIds = Set(projects.map(\.id))
        for row in existing where !fetchedIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
    }

    /// `CachedLabel` has no `update(from:)` because labels are small and
    /// immutable in practice, so the whole set is replaced.
    @MainActor
    func cacheLabels(_ labels: [VLabel]) throws {
        let context = modelContainer.mainContext
        for row in try context.fetch(FetchDescriptor<CachedLabel>()) {
            context.delete(row)
        }
        for label in labels {
            context.insert(CachedLabel(from: label))
        }
        try context.save()
    }

    /// Drops every cached record. Called on an explicit logout so one account's
    /// tasks can't surface under the next.
    @MainActor
    func clearCache() {
        let context = modelContainer.mainContext
        for row in (try? context.fetch(FetchDescriptor<CachedTask>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<CachedProject>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<CachedLabel>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? [] {
            context.delete(row)
        }
        try? context.save()
    }

    // MARK: - Cache Sync

    @MainActor
    func syncTasks() async throws -> [VTask] {
        let tasks = try await taskService.fetchAllTasks(perPage: 200)
        try cacheTasks(tasks)
        return tasks
    }

    @MainActor
    func syncProjects() async throws -> [Project] {
        let projects = try await projectService.fetchProjects()
        try cacheProjects(projects)
        return projects
    }

    // MARK: - Cache Reads

    @MainActor
    func loadCachedTasks() throws -> [VTask] {
        let context = modelContainer.mainContext
        let cached = try context.fetch(FetchDescriptor<CachedTask>())
        return cached.map { $0.toVTask() }
    }

    @MainActor
    func loadCachedProjects() throws -> [Project] {
        let context = modelContainer.mainContext
        let cached = try context.fetch(FetchDescriptor<CachedProject>())
        return cached.map { $0.toProject() }
    }

    @MainActor
    func loadCachedLabels() throws -> [VLabel] {
        let context = modelContainer.mainContext
        let cached = try context.fetch(FetchDescriptor<CachedLabel>())
        return cached.map { $0.toLabel() }
    }

    // MARK: - Local Cache Updates

    @MainActor
    func updateCachedTask(_ task: VTask) {
        let context = modelContainer.mainContext
        let taskId = task.id
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == taskId }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: task)
        } else {
            context.insert(CachedTask(from: task))
        }
        try? context.save()
    }

    @MainActor
    func deleteCachedTask(id: Int64) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }

    @MainActor
    func updateCachedProject(_ project: Project) {
        let context = modelContainer.mainContext
        let projectId = project.id
        let descriptor = FetchDescriptor<CachedProject>(
            predicate: #Predicate { $0.id == projectId }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: project)
        } else {
            context.insert(CachedProject(from: project))
        }
        try? context.save()
    }

    @MainActor
    func deleteCachedProject(id: Int64) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<CachedProject>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }
}
