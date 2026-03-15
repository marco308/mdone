import SwiftUI

struct TaskRow: View {
    @Environment(AppState.self) private var appState
    let task: VTask
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                // Priority color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 4, height: 36)

                // Checkbox
                Button {
                    Task {
                        await appState.toggleTaskDone(task)
                    }
                } label: {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.done ? .green : priorityColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let dueDate = task.dueDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(dueDate, style: .date)
                            }
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }

                        if let labels = task.labels, !labels.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(labels.prefix(3)) { label in
                                    LabelChip(label: label)
                                }
                            }
                        }
                    }
                }

                Spacer()

                if task.priority > 0 {
                    PriorityBadge(priority: task.priorityLevel)
                }
            }
            .padding(.vertical, 4)
            .opacity(task.done ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                Task { await appState.toggleTaskDone(task) }
            } label: {
                Label(task.done ? "Undo" : "Done", systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await appState.deleteTask(task) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task)
        }
    }

    private var priorityColor: Color {
        switch task.priorityLevel {
        case .critical, .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .none: .clear
        }
    }
}
