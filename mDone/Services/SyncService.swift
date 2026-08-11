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
                let endpoint = Endpoint(
                    path: operation.endpointPath,
                    method: HTTPMethod(rawValue: operation.method) ?? .GET
                )

                if endpoint.method == .DELETE {
                    try await apiClient.delete(endpoint)
                } else {
                    try await apiClient.sendRawData(endpoint, bodyData: operation.bodyData)
                }

                context.delete(operation)
                try? context.save()
                logger.info("Successfully processed: \(operation.method) \(operation.endpointPath)")
            } catch {
                operation.retryCount += 1
                logger
                    .error(
                        "Failed operation \(operation.method) \(operation.endpointPath) (attempt \(operation.retryCount)): \(error.localizedDescription)"
                    )

                if operation.retryCount >= SyncService.maxRetries {
                    operation.failed = true
                    logger
                        .error(
                            "Operation marked as failed after \(SyncService.maxRetries) retries: \(operation.method) \(operation.endpointPath)"
                        )
                }

                try? context.save()
            }
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
