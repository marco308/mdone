import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops any beyond that. We schedule under that ceiling and leave a little
    /// headroom for one-off notifications the app may post outside this path.
    static let maxPendingReminders = 60

    enum ReminderOffset: Int, CaseIterable {
        case fifteenMinutes = 15
        case thirtyMinutes = 30
        case oneHour = 60
        case oneDay = 1440

        var label: String {
            switch self {
            case .fifteenMinutes: "15 minutes before"
            case .thirtyMinutes: "30 minutes before"
            case .oneHour: "1 hour before"
            case .oneDay: "1 day before"
            }
        }

        var timeInterval: TimeInterval {
            TimeInterval(rawValue * 60)
        }
    }

    /// A single reminder resolved to the concrete instant it should fire, ready
    /// to be turned into a notification request. Kept as a plain value type so
    /// the prioritization logic is pure and unit-testable without the
    /// notification center.
    struct PlannedReminder: Equatable {
        let identifier: String
        let taskId: Int64
        let title: String
        let fireDate: Date
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Whether the OS currently allows this app to post notifications. Checked
    /// before scheduling so a permission the user revoked in Settings doesn't
    /// leave us "scheduling" reminders iOS silently refuses.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Resolves the concrete fire instant for one `TaskReminder`, preferring
    /// the server-computed absolute `reminder` and falling back to
    /// `relative_period` seconds from the due date. Returns `nil` when neither
    /// is available.
    static func fireDate(for reminder: TaskReminder, dueDate: Date?) -> Date? {
        if let absoluteDate = reminder.reminder {
            return absoluteDate
        }
        if let period = reminder.relativePeriod, let dueDate {
            return dueDate.addingTimeInterval(TimeInterval(period))
        }
        return nil
    }

    /// Resolves every reminder a single task should fire, in the future only.
    /// Pure and side-effect free so it can be composed by both the single-task
    /// and bulk paths and exercised directly in tests.
    static func plannedReminders(
        for task: VTask,
        offset: ReminderOffset,
        now: Date = Date()
    ) -> [PlannedReminder] {
        guard !task.done else { return [] }

        // Per-task reminders take precedence over the app-level offset.
        if let taskReminders = task.reminders, !taskReminders.isEmpty {
            var planned: [PlannedReminder] = []
            for (index, reminder) in taskReminders.enumerated() {
                // Vikunja auto-computes the absolute `reminder` for relative
                // reminders and keeps it current when the referenced date
                // (`relative_to`: due/start/end) changes, so it's the
                // authoritative fire time. Prefer it; only fall back to
                // computing from `relative_period` (negative = before) against
                // the due date when the server sent no absolute value. That
                // fallback assumes `relative_to == due_date`; the preferred
                // path is what makes start/end-relative reminders correct.
                let reminderDate = Self.fireDate(for: reminder, dueDate: task.dueDate)

                guard let date = reminderDate, date > now else { continue }
                planned.append(PlannedReminder(
                    identifier: "task-\(task.id)-\(index)",
                    taskId: task.id,
                    title: task.title,
                    fireDate: date
                ))
            }
            return planned
        }

        // Fall back to a single reminder derived from the due date.
        guard let dueDate = task.dueDate else { return [] }
        let reminderDate = dueDate.addingTimeInterval(-offset.timeInterval)
        guard reminderDate > now else { return [] }
        return [PlannedReminder(
            identifier: "task-\(task.id)",
            taskId: task.id,
            title: task.title,
            fireDate: reminderDate
        )]
    }

    /// Prioritizes the reminders that should actually be registered given the
    /// per-app cap. The soonest-firing reminders win, because those are the
    /// ones the user needs first; ties break on identifier for determinism.
    /// Pure so tests can assert the cap and ordering without the OS.
    static func prioritized(
        _ reminders: [PlannedReminder],
        limit: Int = maxPendingReminders
    ) -> [PlannedReminder] {
        reminders
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate {
                    return lhs.fireDate < rhs.fireDate
                }
                return lhs.identifier < rhs.identifier
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func makeRequest(from planned: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content.body = planned.title
        content.sound = .default
        content.userInfo = ["taskId": planned.taskId]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: planned.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)
    }

    func scheduleTaskReminder(for task: VTask, offset: ReminderOffset = .thirtyMinutes) async {
        cancelTaskReminder(for: task.id)
        let planned = Self.plannedReminders(for: task, offset: offset)
        // A single task can't exceed the cap on its own in practice, but keep
        // it consistent with the bulk path.
        for reminder in Self.prioritized(planned) {
            try? await center.add(makeRequest(from: reminder))
        }
    }

    func cancelTaskReminder(for taskId: Int64) {
        // Remove both single-reminder and multi-reminder identifiers
        let singleId = "task-\(taskId)"
        var identifiers = [singleId]
        // Remove up to 20 indexed reminders (reasonable upper bound)
        for i in 0 ..< 20 {
            identifiers.append("task-\(taskId)-\(i)")
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func scheduleReminders(for tasks: [VTask], offset: ReminderOffset = .thirtyMinutes) async {
        center.removeAllPendingNotificationRequests()

        // Resolve every candidate reminder across all tasks first, then keep
        // only the soonest `maxPendingReminders`. Without this, a large task
        // list would push the total past iOS's 64-notification ceiling and the
        // system would silently drop whichever requests it received last,
        // leaving arbitrary tasks with no reminder at all.
        var candidates: [PlannedReminder] = []
        for task in tasks where !task.done {
            candidates.append(contentsOf: Self.plannedReminders(for: task, offset: offset))
        }

        for reminder in Self.prioritized(candidates) {
            try? await center.add(makeRequest(from: reminder))
        }
    }
}
