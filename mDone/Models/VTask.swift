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
    /// Tasks related to this one, keyed by the raw relation kind (`"subtask"`,
    /// `"parenttask"`, `"blocking"`, …). Kept as raw strings so a kind added
    /// by a future server version can't fail decoding. The embedded tasks are
    /// snapshots without their own relations (`related_tasks` is `null` one
    /// level down; the server doesn't recurse).
    var relatedTasks: [String: [VTask]]?

    var priorityLevel: PriorityLevel {
        PriorityLevel(rawValue: Int(priority)) ?? .none
    }

    /// The related tasks of one kind, in server order. Empty when none.
    func relatedTasks(of kind: RelationKind) -> [VTask] {
        relatedTasks?[kind.rawValue] ?? []
    }

    /// Direct subtasks of this task (including completed ones).
    var subtasks: [VTask] {
        relatedTasks(of: .subtask)
    }

    /// Tasks this one is a subtask of. Vikunja allows more than one parent.
    var parentTasks: [VTask] {
        relatedTasks(of: .parenttask)
    }

    var hasParentTask: Bool {
        !parentTasks.isEmpty
    }

    /// Completed/total counts across direct subtasks, driving the "2/5 done"
    /// badge. `nil` when the task has no subtasks.
    var subtaskCounts: (done: Int, total: Int)? {
        let subs = subtasks
        guard !subs.isEmpty else { return nil }
        return (subs.filter(\.done).count, subs.count)
    }

    var isRepeating: Bool {
        (repeatAfter ?? 0) > 0
    }

    /// The interval picker edits fixed-second recurrences. Preserve Vikunja's
    /// mode only when the interval itself was not changed.
    func repeatModeForEditedRepeatAfter(_ editedRepeatAfter: Int64) -> Int64? {
        editedRepeatAfter == (repeatAfter ?? 0) ? repeatMode : 0
    }

    /// The user-assigned task color from Vikunja, normalized for display.
    /// Returns `nil` when Vikunja sends no color (an empty string) or a value
    /// that isn't a valid 3/6/8-digit hex, so uncolored tasks fall back to the
    /// default styling instead of rendering a stray gray. The leading `#`, if
    /// present, is stripped.
    var normalizedHexColor: String? {
        guard let hexColor else { return nil }
        let trimmed = hexColor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard [3, 6, 8].contains(trimmed.count),
              trimmed.allSatisfy(\.isHexDigit)
        else { return nil }
        return trimmed
    }

    /// `description` with the mDone estimate marker stripped — what the user
    /// should see in editors and previews. `nil` if the description has no
    /// body once the marker is removed.
    var userVisibleDescription: String? {
        EstimateMarker.strip(description)
    }

    /// The optional mDone estimated duration parsed from the description's
    /// trailing marker. `nil` if no estimate is set.
    var estimatedSeconds: TimeInterval? {
        EstimateMarker.parse(description)
    }

    var repeatDescription: String? {
        guard let interval = repeatAfter, interval > 0 else { return nil }
        let hours = interval / 3600
        let days = hours / 24
        if days == 1 { return "Daily" }
        if days == 7 { return "Weekly" }
        if days >= 28 && days <= 31 { return "Monthly" }
        if days == 365 || days == 366 { return "Yearly" }
        if days > 0 { return "Every \(days) days" }
        if hours > 0 { return "Every \(hours) hours" }
        return "Repeating"
    }

    /// Whether the due date has a specific time (not midnight)
    var hasSpecificTime: Bool {
        guard let dueDate = effectiveDueDate else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: dueDate)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0
    }

    /// Returns nil for Vikunja's zero-date sentinel (year 1)
    var effectiveDueDate: Date? {
        guard let dueDate else { return nil }
        if Calendar.current.component(.year, from: dueDate) <= 1 { return nil }
        return dueDate
    }

    /// Returns nil for Vikunja's zero-date sentinel (year 1).
    var effectiveStartDate: Date? {
        guard let startDate else { return nil }
        if Calendar.current.component(.year, from: startDate) <= 1 { return nil }
        return startDate
    }

    /// Returns nil for Vikunja's zero-date sentinel (year 1).
    var effectiveEndDate: Date? {
        guard let endDate else { return nil }
        if Calendar.current.component(.year, from: endDate) <= 1 { return nil }
        return endDate
    }

    /// Whether this task is scheduled for the given local calendar day.
    /// Start/end ranges are inclusive; due dates add another matching day.
    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let dueDate = effectiveDueDate,
           calendar.isDate(dueDate, inSameDayAs: day)
        {
            return true
        }

        switch (effectiveStartDate, effectiveEndDate) {
        case let (startDate?, endDate?):
            let startDay = calendar.startOfDay(for: startDate)
            let endDay = calendar.startOfDay(for: endDate)
            let firstDay = min(startDay, endDay)
            let lastDay = max(startDay, endDay)
            return day >= firstDay && day <= lastDay
        case let (startDate?, nil):
            return calendar.isDate(startDate, inSameDayAs: day)
        case let (nil, endDate?):
            return calendar.isDate(endDate, inSameDayAs: day)
        default:
            return false
        }
    }

    var isOverdue: Bool {
        guard let dueDate = effectiveDueDate, !done else { return false }
        // Date-only tasks (time = 00:00) should only count as overdue once
        // the day they're due is fully past — otherwise they show red the
        // moment they're created, even though Default-due-time may also have
        // landed them at 00:00 (e.g. existing tasks synced from the web).
        if !hasSpecificTime {
            let calendar = Calendar.current
            guard let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: dueDate
            ) else { return dueDate < Date() }
            return endOfDay < Date()
        }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate = effectiveDueDate, !done else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isDueTomorrow: Bool {
        guard let dueDate = effectiveDueDate, !done else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }

    var isDueThisWeek: Bool {
        guard let dueDate = effectiveDueDate, !done else { return false }
        let now = Date()
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))
        else { return false }
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
    var startDate: Date?
    var endDate: Date?
    var priority: Int64?
    var projectId: Int64?
    var labels: [LabelRef]?
    var repeatAfter: Int64?
    var repeatMode: Int64?
    var reminders: [TaskReminder]?
    /// Completion progress, 0...1. Drives the Current section's progress bar.
    var percentDone: Double?
    var clearDueDate: Bool?
    var clearStartDate: Bool?
    var clearEndDate: Bool?

    struct LabelRef: Encodable {
        var id: Int64
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, done, dueDate, startDate, endDate, priority, projectId, labels
        case repeatAfter, repeatMode, reminders, percentDone
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(done, forKey: .done)
        if clearDueDate == true {
            try container.encode(Date.distantPast, forKey: .dueDate)
        } else {
            try container.encodeIfPresent(dueDate, forKey: .dueDate)
        }
        if clearStartDate == true {
            try container.encode(Date.distantPast, forKey: .startDate)
        } else {
            try container.encodeIfPresent(startDate, forKey: .startDate)
        }
        if clearEndDate == true {
            try container.encode(Date.distantPast, forKey: .endDate)
        } else {
            try container.encodeIfPresent(endDate, forKey: .endDate)
        }
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(repeatAfter, forKey: .repeatAfter)
        try container.encodeIfPresent(repeatMode, forKey: .repeatMode)
        try container.encodeIfPresent(reminders, forKey: .reminders)
        try container.encodeIfPresent(percentDone, forKey: .percentDone)
    }

    /// Carries schedule fields forward for Vikunja task updates, which can
    /// otherwise clear omitted values on partial mutations such as Done or Progress.
    func preservingSchedule(from task: VTask) -> TaskUpdateRequest {
        var request = self
        if request.dueDate == nil, request.clearDueDate != true {
            request.dueDate = task.effectiveDueDate
        }
        if request.startDate == nil, request.clearStartDate != true {
            request.startDate = task.effectiveStartDate
        }
        if request.endDate == nil, request.clearEndDate != true {
            request.endDate = task.effectiveEndDate
        }
        if request.repeatAfter == nil {
            request.repeatAfter = task.repeatAfter
        }
        if request.repeatMode == nil {
            request.repeatMode = task.repeatMode
        }
        if request.reminders == nil {
            request.reminders = task.reminders
        }
        return request
    }
}
