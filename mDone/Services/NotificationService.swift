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

    /// Resolves the concrete fire instant for one `TaskReminder`.
    ///
    /// A relative reminder is computed locally from `relative_period` against
    /// the date it points at (`relative_to`: due, start or end date), because
    /// that date can change on this device before the server has recomputed
    /// the absolute `reminder`. An offline postpone, for example, moves the
    /// due date but leaves the old absolute value in place until the queued
    /// edit syncs. The server's absolute value is the fallback when the
    /// referenced date is unknown here, and is the whole answer for a plain
    /// absolute reminder. Returns `nil` when neither is available.
    static func fireDate(for reminder: TaskReminder, task: VTask) -> Date? {
        if let period = reminder.relativePeriod,
           let base = referenceDate(for: reminder.relativeTo, in: task)
        {
            return base.addingTimeInterval(TimeInterval(period))
        }
        return reminder.reminder
    }

    /// The task date a relative reminder is anchored to. Vikunja sends
    /// `due_date`, `start_date` or `end_date`; a missing value is treated as
    /// the due date, which is what the app assumed before.
    private static func referenceDate(for relativeTo: String?, in task: VTask) -> Date? {
        switch relativeTo {
        case "start_date": task.effectiveStartDate
        case "end_date": task.effectiveEndDate
        default: task.effectiveDueDate
        }
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
                let reminderDate = Self.fireDate(for: reminder, task: task)

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

    /// Replaces the pending reminders with the ones `tasks` calls for.
    ///
    /// Callers fire this from every task mutation as well as from refreshes,
    /// so calls overlap. Each rebuild waits for the previous one and cancels
    /// it first, so two rebuilds never interleave their `center.add` calls.
    /// Interleaving let an older rebuild, working from a stale task list,
    /// re-add a reminder for a task that had since been deleted or completed,
    /// and could push the total past the 64-request ceiling again.
    func scheduleReminders(for tasks: [VTask], offset: ReminderOffset = .thirtyMinutes) async {
        let previous = rebuild
        previous?.cancel()
        let current = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await self.applyReminders(for: tasks, offset: offset)
        }
        rebuild = current
        await current.value
    }

    private var rebuild: Task<Void, Never>?

    /// Resolves every candidate reminder across all tasks, keeps the soonest
    /// `maxPendingReminders`, and reconciles the pending requests against
    /// that set instead of wiping them all first.
    ///
    /// Without the cap, a large task list would push the total past iOS's
    /// 64-notification ceiling and the system would silently drop whichever
    /// requests it received last. Reconciling rather than removing everything
    /// up front means a rebuild cut short, by a newer rebuild or by the app
    /// being suspended in the background, leaves the previous reminders in
    /// place instead of none at all. Adding a request whose identifier is
    /// already pending replaces it, so unchanged reminders are simply updated.
    private func applyReminders(for tasks: [VTask], offset: ReminderOffset) async {
        var candidates: [PlannedReminder] = []
        for task in tasks where !task.done {
            candidates.append(contentsOf: Self.plannedReminders(for: task, offset: offset))
        }
        let wanted = Self.prioritized(candidates)

        let pendingIds = await center.pendingNotificationRequests().map(\.identifier)
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(
            withIdentifiers: Self.staleIdentifiers(pending: pendingIds, wanted: wanted)
        )

        for reminder in wanted {
            guard !Task.isCancelled else { return }
            try? await center.add(makeRequest(from: reminder))
        }
    }

    /// Pending reminder identifiers that are no longer wanted. Only `task-`
    /// identifiers are touched, so a notification scheduled by some other part
    /// of the app is never removed by a reminder rebuild.
    static func staleIdentifiers(pending: [String], wanted: [PlannedReminder]) -> [String] {
        let wantedIds = Set(wanted.map(\.identifier))
        return pending.filter { $0.hasPrefix("task-") && !wantedIds.contains($0) }
    }
}
