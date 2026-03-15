import Foundation
import SwiftData
import OSLog

actor SyncService {
    private let taskService: TaskService
    private let projectService: ProjectService
    private let modelContainer: ModelContainer
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.mdone", category: "SyncService")

    private static let maxRetries = 3

    init(taskService: TaskService, projectService: ProjectService, modelContainer: ModelContainer, apiClient: APIClient = .shared) {
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
                logger.error("Failed operation \(operation.method) \(operation.endpointPath) (attempt \(operation.retryCount)): \(error.localizedDescription)")

                if operation.retryCount >= SyncService.maxRetries {
                    operation.failed = true
                    logger.error("Operation marked as failed after \(SyncService.maxRetries) retries: \(operation.method) \(operation.endpointPath)")
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

    // MARK: - Cache Sync

    @MainActor
    func syncTasks() async throws -> [VTask] {
        let tasks = try await taskService.fetchAllTasks(perPage: 200)

        let context = modelContainer.mainContext
        let existingTasks = try context.fetch(FetchDescriptor<CachedTask>())
        let existingById = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })

        for task in tasks {
            if let cached = existingById[task.id] {
                cached.update(from: task)
            } else {
                context.insert(CachedTask(from: task))
            }
        }

        let fetchedIds = Set(tasks.map(\.id))
        for existing in existingTasks where !fetchedIds.contains(existing.id) {
            context.delete(existing)
        }

        try context.save()
        return tasks
    }

    @MainActor
    func syncProjects() async throws -> [Project] {
        let projects = try await projectService.fetchProjects()

        let context = modelContainer.mainContext
        let existingProjects = try context.fetch(FetchDescriptor<CachedProject>())
        let existingById = Dictionary(uniqueKeysWithValues: existingProjects.map { ($0.id, $0) })

        for project in projects {
            if let cached = existingById[project.id] {
                cached.update(from: project)
            } else {
                context.insert(CachedProject(from: project))
            }
        }

        let fetchedIds = Set(projects.map(\.id))
        for existing in existingProjects where !fetchedIds.contains(existing.id) {
            context.delete(existing)
        }

        try context.save()
        return projects
    }

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
}
