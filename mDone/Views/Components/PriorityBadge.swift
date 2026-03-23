import SwiftUI

struct PriorityBadge: View {
    let priority: PriorityLevel

    var body: some View {
        if priority != .none {
            Image(systemName: "flag.fill")
                .font(.caption2)
                .foregroundStyle(color)
                .accessibilityLabel("Priority: \(priority.label)")
        }
    }

    private var color: Color {
        switch priority {
        case .critical, .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .none: .gray
        }
    }
}
