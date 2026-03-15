import Foundation
import SwiftData

@Model
final class CachedTask {
    @Attribute(.unique) var id: Int64
    var title: String
    var taskDescription: String?
    var done: Bool
    var doneAt: Date?
    var dueDate: Date?
    var priority: Int64
    var projectId: Int64
    var hexColor: String?
    var percentDone: Double?
    var isFavorite: Bool
    var created: Date?
    var updated: Date?
    var labelsData: Data?

    init(from task: VTask) {
        self.id = task.id
        self.title = task.title
        self.taskDescription = task.description
        self.done = task.done
        self.doneAt = task.doneAt
        self.dueDate = task.dueDate
        self.priority = task.priority
        self.projectId = task.projectId
        self.hexColor = task.hexColor
        self.percentDone = task.percentDone
        self.isFavorite = task.isFavorite ?? false
        self.created = task.created
        self.updated = task.updated
        self.labelsData = try? JSONEncoder().encode(task.labels)
    }

    func toVTask() -> VTask {
        let labels: [VLabel]? = if let labelsData {
            try? JSONDecoder().decode([VLabel].self, from: labelsData)
        } else {
            nil
        }

        return VTask(
            id: id,
            title: title,
            description: taskDescription,
            done: done,
            doneAt: doneAt,
            dueDate: dueDate,
            priority: priority,
            projectId: projectId,
            hexColor: hexColor,
            percentDone: percentDone,
            isFavorite: isFavorite,
            labels: labels,
            created: created,
            updated: updated
        )
    }

    func update(from task: VTask) {
        self.title = task.title
        self.taskDescription = task.description
        self.done = task.done
        self.doneAt = task.doneAt
        self.dueDate = task.dueDate
        self.priority = task.priority
        self.projectId = task.projectId
        self.hexColor = task.hexColor
        self.percentDone = task.percentDone
        self.isFavorite = task.isFavorite ?? false
        self.created = task.created
        self.updated = task.updated
        self.labelsData = try? JSONEncoder().encode(task.labels)
    }
}

@Model
final class CachedProject {
    @Attribute(.unique) var id: Int64
    var title: String
    var projectDescription: String?
    var hexColor: String?
    var isArchived: Bool
    var isFavorite: Bool
    var position: Double?
    var created: Date?
    var updated: Date?

    init(from project: Project) {
        self.id = project.id
        self.title = project.title
        self.projectDescription = project.description
        self.hexColor = project.hexColor
        self.isArchived = project.isArchived ?? false
        self.isFavorite = project.isFavorite ?? false
        self.position = project.position
        self.created = project.created
        self.updated = project.updated
    }

    func toProject() -> Project {
        Project(
            id: id,
            title: title,
            description: projectDescription,
            hexColor: hexColor,
            isArchived: isArchived,
            isFavorite: isFavorite,
            position: position,
            created: created,
            updated: updated
        )
    }

    func update(from project: Project) {
        self.title = project.title
        self.projectDescription = project.description
        self.hexColor = project.hexColor
        self.isArchived = project.isArchived ?? false
        self.isFavorite = project.isFavorite ?? false
        self.position = project.position
        self.created = project.created
        self.updated = project.updated
    }
}

@Model
final class CachedLabel {
    @Attribute(.unique) var id: Int64
    var title: String
    var hexColor: String?
    var labelDescription: String?
    var created: Date?
    var updated: Date?

    init(from label: VLabel) {
        self.id = label.id
        self.title = label.title
        self.hexColor = label.hexColor
        self.labelDescription = label.description
        self.created = label.created
        self.updated = label.updated
    }

    func toLabel() -> VLabel {
        VLabel(
            id: id,
            title: title,
            hexColor: hexColor,
            description: labelDescription,
            created: created,
            updated: updated
        )
    }
}

@Model
final class PendingOperation {
    var id: UUID
    var endpointPath: String
    var method: String
    var bodyData: Data?
    var timestamp: Date

    init(endpointPath: String, method: String, bodyData: Data? = nil) {
        self.id = UUID()
        self.endpointPath = endpointPath
        self.method = method
        self.bodyData = bodyData
        self.timestamp = Date()
    }
}
