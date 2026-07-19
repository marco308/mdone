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

    var priorityLevel: PriorityLevel {
        PriorityLevel(rawValue: Int(priority)) ?? .none
    }

    var isRepeating: Bool {
        (repeatAfter ?? 0) > 0
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
    var priority: Int64?
    var projectId: Int64?
    var labels: [LabelRef]?
    var repeatAfter: Int64?
    var reminders: [TaskReminder]?
    /// Completion progress, 0...1. Drives the Current section's progress bar.
    var percentDone: Double?
    var clearDueDate: Bool?

    struct LabelRef: Encodable {
        var id: Int64
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, done, dueDate, priority, projectId, labels, repeatAfter, reminders, percentDone
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
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(repeatAfter, forKey: .repeatAfter)
        try container.encodeIfPresent(reminders, forKey: .reminders)
        try container.encodeIfPresent(percentDone, forKey: .percentDone)
    }
}
