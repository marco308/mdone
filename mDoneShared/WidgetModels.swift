import Foundation
import SwiftUI

struct WidgetTask: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let description: String
    let done: Bool
    let dueDate: Date?
    let priority: Int
    let projectId: Int64
    let projectTitle: String?
    let hexColor: String?
    let isOverdue: Bool
    
    var parsedColor: Color? {
        guard let hex = hexColor, !hex.isEmpty else { return nil }
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&int)
        
        let r, g, b: Double
        if cleanedHex.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return nil
    }

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

struct WidgetProject: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let hexColor: String?
    
    var parsedColor: Color? {
        guard let hex = hexColor, !hex.isEmpty else { return nil }
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&int)
        
        let r, g, b: Double
        if cleanedHex.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return nil
    }
}

struct WidgetData: Codable {
    let todayTasks: [WidgetTask]
    let upcomingTasks: [WidgetTask]
    let overdueTasks: [WidgetTask]
    let projects: [WidgetProject]
    let lastUpdated: Date
}
