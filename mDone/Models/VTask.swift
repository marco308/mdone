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
    /// How many comments the task has. Only list reads ask for it
    /// (`expand=comment_count`); a single task or an update answer leaves it
    /// out, which is why `AppState.commentCounts` keeps its own copy (#2).
    var commentCount: Int64?
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

    /// Whether this task repeats. Delegates to `TaskRecurrence` rather than
    /// reading `repeatAfter`, which alone misses Vikunja's monthly mode: that
    /// mode carries `repeat_after = 0`, so a monthly task used to be invisible
    /// as a repeating one everywhere in the app (issue #35).
    var isRepeating: Bool {
        recurrence != nil
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
        HexColor.normalized(hexColor)
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
        recurrence?.label
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
        if Calendar.current.component(.year, from: dueDate) <= 1 {
            return nil
        }
        return dueDate
    }

    /// Returns nil for Vikunja's zero-date sentinel (year 1).
    var effectiveStartDate: Date? {
        guard let startDate else { return nil }
        if Calendar.current.component(.year, from: startDate) <= 1 {
            return nil
        }
        return startDate
    }

    /// Returns nil for Vikunja's zero-date sentinel (year 1).
    var effectiveEndDate: Date? {
        guard let endDate else { return nil }
        if Calendar.current.component(.year, from: endDate) <= 1 {
            return nil
        }
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

    /// The start-of-day keys within [rangeStart, rangeEnd) on which this task
    /// occurs, per the same rules as `occurs(on:)`. Both bounds are expected
    /// to be day boundaries (e.g. a month's first midnights).
    func occurrenceDays(from rangeStart: Date, before rangeEnd: Date, calendar: Calendar = .current) -> [Date] {
        var days: Set<Date> = []

        func insertDay(of date: Date) {
            let day = calendar.startOfDay(for: date)
            if day >= rangeStart, day < rangeEnd {
                days.insert(day)
            }
        }

        if let dueDate = effectiveDueDate {
            insertDay(of: dueDate)
        }

        switch (effectiveStartDate, effectiveEndDate) {
        case let (startDate?, endDate?):
            let firstDay = calendar.startOfDay(for: min(startDate, endDate))
            let lastDay = calendar.startOfDay(for: max(startDate, endDate))
            var day = max(firstDay, rangeStart)
            while day <= lastDay, day < rangeEnd {
                days.insert(day)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        case let (startDate?, nil):
            insertDay(of: startDate)
        case let (nil, endDate?):
            insertDay(of: endDate)
        default:
            break
        }

        return days.sorted()
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

    /// Vikunja echoes a fixed-time reminder back as `relative_period: 0` and
    /// `relative_to: ""` rather than leaving them out, so a non-nil
    /// `relativePeriod` does not make a reminder relative. Only `relativeTo`
    /// says so. Reading the period alone showed a 12 PM reminder as
    /// "At time of due date" and fired it at the due time (#242).
    var isRelative: Bool {
        !(relativeTo ?? "").isEmpty
    }

    /// When this reminder should fire for `task`. A relative reminder is
    /// worked out from the task's own date, since the `reminder` Vikunja
    /// computes for it goes stale as soon as that date is edited locally.
    /// Nil when the date it hangs off is unset.
    func fireDate(for task: VTask) -> Date? {
        guard isRelative else { return reminder }
        let anchor: Date? = switch relativeTo {
        case "start_date": task.effectiveStartDate
        case "end_date": task.effectiveEndDate
        default: task.effectiveDueDate
        }
        return anchor?.addingTimeInterval(TimeInterval(relativePeriod ?? 0))
    }
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
        case .none: String(localized: "None")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .urgent: String(localized: "Urgent")
        case .critical: String(localized: "Critical")
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

/// The body of a task update, sent as a JSON Merge Patch (#292).
///
/// A nil field is left out of the body, and the server keeps whatever the task
/// has. Only what a caller sets reaches the server, so an update can never wipe
/// a field it did not mean to touch, and never overwrites a change made in
/// another client since the task was last read.
struct TaskUpdateRequest: Encodable, Equatable {
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
    var hexColor: String?
    var isFavorite: Bool?
    /// Who the task is assigned to, encoded as ids only. Only sent when the
    /// assignees were changed: an empty list unassigns everyone.
    var assignees: [User]?
    /// Sent as `null`, which clears the date.
    var clearDueDate: Bool?
    var clearStartDate: Bool?
    var clearEndDate: Bool?

    struct LabelRef: Encodable, Equatable {
        var id: Int64
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, done, dueDate, startDate, endDate, priority, projectId, labels
        case repeatAfter, repeatMode, reminders, percentDone, hexColor, isFavorite, assignees
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(done, forKey: .done)
        if clearDueDate == true {
            try container.encodeNil(forKey: .dueDate)
        } else {
            try container.encodeIfPresent(dueDate, forKey: .dueDate)
        }
        if clearStartDate == true {
            try container.encodeNil(forKey: .startDate)
        } else {
            try container.encodeIfPresent(startDate, forKey: .startDate)
        }
        if clearEndDate == true {
            try container.encodeNil(forKey: .endDate)
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
        try container.encodeIfPresent(hexColor, forKey: .hexColor)
        try container.encodeIfPresent(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(assignees?.map { UserRef(id: $0.id) }, forKey: .assignees)
    }

    /// True when there is nothing to send.
    var isEmpty: Bool {
        self == TaskUpdateRequest()
    }

    /// Drops every field that already matches `task`, so that saving the task
    /// editor, which fills in every field it shows, sends only what the user
    /// changed (#292). A field that was not edited is left to the server, so a
    /// change made to it in another client survives.
    ///
    /// nil and empty count as the same value for the description, reminders
    /// and assignees, as do nil and zero for the repeat fields, because Vikunja
    /// reports an unset field either way.
    func onlyChanges(from task: VTask) -> TaskUpdateRequest {
        var request = self
        if request.title == task.title {
            request.title = nil
        }
        if let description = request.description, description == (task.description ?? "") {
            request.description = nil
        }
        if request.done == task.done {
            request.done = nil
        }
        if request.priority == task.priority {
            request.priority = nil
        }
        if request.projectId == task.projectId {
            request.projectId = nil
        }
        if let repeatAfter = request.repeatAfter, repeatAfter == (task.repeatAfter ?? 0) {
            request.repeatAfter = nil
        }
        if let repeatMode = request.repeatMode, repeatMode == (task.repeatMode ?? 0) {
            request.repeatMode = nil
        }
        if let reminders = request.reminders, reminders == (task.reminders ?? []) {
            request.reminders = nil
        }
        if request.percentDone == task.percentDone
            || (request.percentDone == 0 && task.percentDone == nil)
        {
            request.percentDone = nil
        }
        if request.hexColor == task.hexColor {
            request.hexColor = nil
        }
        if request.isFavorite == task.isFavorite {
            request.isFavorite = nil
        }
        if let assignees = request.assignees,
           assignees.map(\.id) == (task.assignees ?? []).map(\.id)
        {
            request.assignees = nil
        }
        Self.dropUnchangedDate(&request.dueDate, clear: &request.clearDueDate, current: task.effectiveDueDate)
        Self.dropUnchangedDate(&request.startDate, clear: &request.clearStartDate, current: task.effectiveStartDate)
        Self.dropUnchangedDate(&request.endDate, clear: &request.clearEndDate, current: task.effectiveEndDate)
        return request
    }

    /// Clearing a date the task does not have, or setting the one it has
    /// already, is no change. A clear flag wins over a date, as in `encode`.
    private static func dropUnchangedDate(_ date: inout Date?, clear: inout Bool?, current: Date?) {
        if clear == true {
            date = nil
            if current == nil {
                clear = nil
            }
            return
        }
        clear = nil
        if let value = date, value == current {
            date = nil
        }
    }
}
