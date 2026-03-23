import SwiftUI

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case highPriority
    case dueThisWeek
    case completed
    case hasLabels

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .highPriority: return "High Priority"
        case .dueThisWeek: return "Due This Week"
        case .completed: return "Completed"
        case .hasLabels: return "Has Labels"
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .highPriority: return "flag.fill"
        case .dueThisWeek: return "calendar"
        case .completed: return "checkmark.circle"
        case .hasLabels: return "tag"
        }
    }

    /// Returns the Vikunja filter syntax string for server-side filtering.
    var filterString: String? {
        switch self {
        case .all:
            return nil
        case .highPriority:
            return "priority >= 3"
        case .dueThisWeek:
            return "due_date > now && due_date < now+7d"
        case .completed:
            return "done = true"
        case .hasLabels:
            // Vikunja does not have a direct "has labels" filter;
            // this is applied locally instead.
            return nil
        }
    }

    /// Applies the filter locally to an array of tasks.
    func apply(to tasks: [VTask]) -> [VTask] {
        switch self {
        case .all:
            return tasks
        case .highPriority:
            return tasks.filter { $0.priority >= 3 }
        case .dueThisWeek:
            return tasks.filter { $0.isDueThisWeek || $0.isDueToday }
        case .completed:
            return tasks.filter { $0.done }
        case .hasLabels:
            return tasks.filter { !($0.labels ?? []).isEmpty }
        }
    }
}

struct FilterBar: View {
    @Binding var activeFilter: TaskFilter?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases) { filter in
                    FilterChip(
                        title: filter.label,
                        icon: filter.icon,
                        isSelected: isSelected(filter)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if filter == .all {
                                activeFilter = nil
                            } else if activeFilter == filter {
                                activeFilter = nil
                            } else {
                                activeFilter = filter
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }

    private func isSelected(_ filter: TaskFilter) -> Bool {
        if filter == .all {
            return activeFilter == nil
        }
        return activeFilter == filter
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
