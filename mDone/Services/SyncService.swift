import Foundation
import SwiftData

actor SyncService {
    private let taskService: TaskService
    private let projectService: ProjectService
    private let modelContainer: ModelContainer

    init(taskService: TaskService, projectService: ProjectService, modelContainer: ModelContainer) {
        self.taskService = taskService
        self.projectService = projectService
        self.modelContainer = modelContainer
    }

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
}
