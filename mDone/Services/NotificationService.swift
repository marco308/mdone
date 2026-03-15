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
        guard let dueDate = task.dueDate, !task.done else { return }

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

    func cancelTaskReminder(for taskId: Int64) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskId)"])
    }

    func scheduleReminders(for tasks: [VTask], offset: ReminderOffset = .thirtyMinutes) async {
        center.removeAllPendingNotificationRequests()
        for task in tasks where task.dueDate != nil && !task.done {
            await scheduleTaskReminder(for: task, offset: offset)
        }
    }
}
