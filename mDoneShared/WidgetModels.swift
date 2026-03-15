import Foundation
import SwiftUI

struct WidgetTask: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let done: Bool
    let dueDate: Date?
    let priority: Int
    let projectId: Int64
    let projectTitle: String?
    let isOverdue: Bool

    var priorityColor: Color {
        switch priority {
        case 1: .blue
        case 2: .yellow
        case 3: .orange
        case 4: .red
        case 5: .purple
        default: .gray
        }
    }
}

struct WidgetData: Codable {
    let todayTasks: [WidgetTask]
    let upcomingTasks: [WidgetTask]
    let overdueTasks: [WidgetTask]
    let lastUpdated: Date
}
