import Foundation

struct VTask: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var description: String?
    var done: Bool
    var doneAt: Date?
    var dueDate: Date?
    var startDate: Date?
    var endDate: Date?
    var priority: Int64
    var projectId: Int64
    var hexColor: String?
    var percentDone: Double?
    var uid: String?
    var position: Double?
    var isFavorite: Bool?
    var repeatAfter: Int64?
    var repeatMode: Int64?
    var identifier: String?
    var index: Int64?
    var reminders: [TaskReminder]?
    var assignees: [User]?
    var labels: [VLabel]?
    var createdBy: User?
    var created: Date?
    var updated: Date?
    var bucketId: Int64?
    var coverImageAttachmentId: Int64?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VTask, rhs: VTask) -> Bool {
        lhs.id == rhs.id
    }

    var priorityLevel: PriorityLevel {
        PriorityLevel(rawValue: Int(priority)) ?? .none
    }

    var isOverdue: Bool {
        guard let dueDate, !done else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate, !done else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isDueThisWeek: Bool {
        guard let dueDate, !done else { return false }
        let now = Date()
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) else { return false }
        return dueDate > now && dueDate <= weekEnd
    }
}

struct TaskReminder: Codable, Hashable {
    var reminder: Date?
    var relativePeriod: Int64?
    var relativeTo: String?
}

enum PriorityLevel: Int, CaseIterable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
    case critical = 5

    var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        case .critical: "Critical"
        }
    }
}

struct TaskCreateRequest: Encodable {
    var title: String
    var description: String?
    var dueDate: Date?
    var priority: Int64?
    var labels: [LabelRef]?

    struct LabelRef: Encodable {
        var id: Int64
    }
}

struct TaskUpdateRequest: Encodable {
    var title: String?
    var description: String?
    var done: Bool?
    var dueDate: Date?
    var priority: Int64?
    var projectId: Int64?
    var labels: [LabelRef]?

    struct LabelRef: Encodable {
        var id: Int64
    }
}
