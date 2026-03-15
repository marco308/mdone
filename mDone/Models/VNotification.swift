import Foundation
import SwiftUI

struct VNotification: Codable, Identifiable {
    let id: Int64
    var name: String?
    var notification: NotificationPayload?
    var read: Bool?
    var readAt: Date?
    var created: Date?

    struct NotificationPayload: Codable {
        var doer: User?
        var task: VTask?
        var project: Project?
        var comment: TaskComment?
    }

    var isUnread: Bool {
        read != true
    }

    var descriptionText: String {
        guard let notification else { return name ?? "Notification" }

        let doerName = notification.doer?.displayName ?? "Someone"

        if let task = notification.task {
            if notification.comment != nil {
                return "\(doerName) commented on \"\(task.title)\""
            }
            return "\(doerName) updated \"\(task.title)\""
        }

        if let project = notification.project {
            return "\(doerName) updated project \"\(project.title)\""
        }

        return name ?? "Notification"
    }

    var iconName: String {
        guard let notification else { return "bell.fill" }

        if notification.comment != nil {
            return "text.bubble.fill"
        }
        if notification.task != nil {
            return "checkmark.circle.fill"
        }
        if notification.project != nil {
            return "folder.fill"
        }
        return "bell.fill"
    }

    var iconColor: Color {
        guard let notification else { return .blue }

        if notification.comment != nil {
            return .orange
        }
        if notification.task != nil {
            return .green
        }
        if notification.project != nil {
            return .purple
        }
        return .blue
    }

    var relativeTimeString: String {
        guard let created else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: created, relativeTo: Date())
    }
}

struct TaskComment: Codable {
    var id: Int64?
    var comment: String?
    var author: User?
    var created: Date?
}
