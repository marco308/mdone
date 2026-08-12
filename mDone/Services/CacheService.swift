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
    var startDate: Date?
    var endDate: Date?
    var priority: Int64
    var projectId: Int64
    var hexColor: String?
    var percentDone: Double?
    var isFavorite: Bool
    var created: Date?
    var updated: Date?
    var labelsData: Data?

    init(from task: VTask) {
        id = task.id
        title = task.title
        taskDescription = task.description
        done = task.done
        doneAt = task.doneAt
        dueDate = task.dueDate
        startDate = task.startDate
        endDate = task.endDate
        priority = task.priority
        projectId = task.projectId
        hexColor = task.hexColor
        percentDone = task.percentDone
        isFavorite = task.isFavorite ?? false
        created = task.created
        updated = task.updated
        labelsData = try? JSONEncoder().encode(task.labels)
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
            startDate: startDate,
            endDate: endDate,
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
        title = task.title
        taskDescription = task.description
        done = task.done
        doneAt = task.doneAt
        dueDate = task.dueDate
        startDate = task.startDate
        endDate = task.endDate
        priority = task.priority
        projectId = task.projectId
        hexColor = task.hexColor
        percentDone = task.percentDone
        isFavorite = task.isFavorite ?? false
        created = task.created
        updated = task.updated
        labelsData = try? JSONEncoder().encode(task.labels)
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
        id = project.id
        title = project.title
        projectDescription = project.description
        hexColor = project.hexColor
        isArchived = project.isArchived ?? false
        isFavorite = project.isFavorite ?? false
        position = project.position
        created = project.created
        updated = project.updated
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
        title = project.title
        projectDescription = project.description
        hexColor = project.hexColor
        isArchived = project.isArchived ?? false
        isFavorite = project.isFavorite ?? false
        position = project.position
        created = project.created
        updated = project.updated
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
        id = label.id
        title = label.title
        hexColor = label.hexColor
        labelDescription = label.description
        created = label.created
        updated = label.updated
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
final class FocusRecord {
    var taskId: Int64
    var taskTitle: String
    var projectName: String
    var priorityLevel: Int
    var startedAt: Date
    var endedAt: Date
    var focusedSeconds: Double
    var device: String

    /// Idempotency key for the focus-service outbox (mdone#62). Optional so
    /// pre-outbox records migrate without a custom plan — the outbox fills
    /// this in lazily before its first delivery attempt.
    var clientId: String?

    /// Set when the focus-service has accepted (or duplicate-acknowledged)
    /// this record. nil = pending delivery; the outbox drain picks these up.
    var deliveredAt: Date?

    /// Set when the focus-service permanently rejected this record (e.g. 422
    /// schema mismatch). The outbox stops retrying these rather than looping
    /// the same bad payload forever. Distinct from `deliveredAt` so the
    /// Settings UI can surface "X records were rejected" separately from
    /// successful delivery counts.
    var discardedAt: Date?

    init(
        taskId: Int64,
        taskTitle: String,
        projectName: String,
        priorityLevel: Int,
        startedAt: Date,
        endedAt: Date,
        focusedSeconds: Double,
        device: String,
        clientId: String? = nil,
        deliveredAt: Date? = nil,
        discardedAt: Date? = nil
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.projectName = projectName
        self.priorityLevel = priorityLevel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds
        self.device = device
        self.clientId = clientId
        self.deliveredAt = deliveredAt
        self.discardedAt = discardedAt
    }
}

@Model
final class PendingOperation {
    var id: UUID
    var endpointPath: String
    var method: String
    var bodyData: Data?
    var timestamp: Date
    var retryCount: Int
    var failed: Bool

    /// How `SyncService` should replay this operation. Optional so the store
    /// migrates without a custom plan; a nil kind means the pre-#146 behaviour
    /// of sending `bodyData` verbatim.
    var kind: String?

    /// The task a `.taskEdit` / `.taskDelete` operation targets. Lets the queue
    /// coalesce repeat edits of one task and drop edits superseded by a delete.
    var taskId: Int64?

    /// Why the operation was abandoned after exhausting its retries, kept so the
    /// UI can tell the user which change didn't make it and why.
    var failureReason: String?

    enum Kind: String {
        /// `bodyData` holds a `QueuedTaskEdit`: re-read the task, merge, then send.
        case taskEdit
        /// No body; delete `taskId`.
        case taskDelete
    }

    var operationKind: Kind? {
        kind.flatMap(Kind.init(rawValue:))
    }

    init(
        endpointPath: String,
        method: String,
        bodyData: Data? = nil,
        kind: Kind? = nil,
        taskId: Int64? = nil
    ) {
        id = UUID()
        self.endpointPath = endpointPath
        self.method = method
        self.bodyData = bodyData
        self.kind = kind?.rawValue
        self.taskId = taskId
        timestamp = Date()
        retryCount = 0
        failed = false
    }
}
