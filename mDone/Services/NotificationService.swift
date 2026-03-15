import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

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

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleTaskReminder(for task: VTask, offset: ReminderOffset = .thirtyMinutes) async {
        guard !task.done else { return }

        // Use per-task reminders if available, otherwise fall back to app-level offset
        if let taskReminders = task.reminders, !taskReminders.isEmpty {
            cancelTaskReminder(for: task.id)
            for (index, reminder) in taskReminders.enumerated() {
                let reminderDate: Date?
                if let period = reminder.relativePeriod, let dueDate = task.dueDate {
                    reminderDate = dueDate.addingTimeInterval(TimeInterval(period))
                } else if let absoluteDate = reminder.reminder {
                    reminderDate = absoluteDate
                } else {
                    continue
                }

                guard let date = reminderDate, date > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Task Due"
                content.body = task.title
                content.sound = .default
                content.userInfo = ["taskId": task.id]

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

                let request = UNNotificationRequest(
                    identifier: "task-\(task.id)-\(index)",
                    content: content,
                    trigger: trigger
                )

                try? await center.add(request)
            }
        } else {
            guard let dueDate = task.dueDate else { return }

            let reminderDate = dueDate.addingTimeInterval(-offset.timeInterval)
            guard reminderDate > Date() else { return }

            let content = UNMutableNotificationContent()
            content.title = "Task Due"
            content.body = task.title
            content.sound = .default
            content.userInfo = ["taskId": task.id]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: "task-\(task.id)",
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    func cancelTaskReminder(for taskId: Int64) {
        // Remove both single-reminder and multi-reminder identifiers
        let singleId = "task-\(taskId)"
        var identifiers = [singleId]
        // Remove up to 20 indexed reminders (reasonable upper bound)
        for i in 0..<20 {
            identifiers.append("task-\(taskId)-\(i)")
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func scheduleReminders(for tasks: [VTask], offset: ReminderOffset = .thirtyMinutes) async {
        center.removeAllPendingNotificationRequests()
        for task in tasks where !task.done {
            let hasReminders = task.reminders != nil && !task.reminders!.isEmpty
            let hasDueDate = task.dueDate != nil
            guard hasReminders || hasDueDate else { continue }
            await scheduleTaskReminder(for: task, offset: offset)
        }
    }
}
