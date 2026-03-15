import SwiftUI

struct TaskRow: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    let task: VTask
    @State private var showDetail = false

    #if os(iOS)
    private var isFocused: Bool {
        focusManager.focusedTaskId == task.id
    }
    #endif

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 4, height: 36)

                Button {
                    Task {
                        await appState.toggleTaskDone(task)
                    }
                } label: {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.done ? .green : checkboxColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let dueDate = task.effectiveDueDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(dueDate, style: .date)
                            }
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }

                        if task.isRepeating {
                            HStack(spacing: 4) {
                                Image(systemName: "repeat")
                                if let desc = task.repeatDescription {
                                    Text(desc)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                #if os(iOS)
                if isFocused {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                }
                #endif
            }
            .padding(.vertical, 4)
            .opacity(task.done ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .listRowBackground(isFocused ? Color.orange.opacity(0.08) : nil)
        #endif
        .swipeActions(edge: .leading) {
            #if os(iOS)
            Button {
                if isFocused {
                    focusManager.endFocus()
                } else {
                    let projectName = appState.projects.first(where: { $0.id == task.projectId })?.title ?? "Inbox"
                    focusManager.switchFocus(task: task, projectName: projectName)
                }
            } label: {
                Label(isFocused ? "End Focus" : "Focus", systemImage: "scope")
            }
            .tint(.orange)
            #endif

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
        #if os(iOS)
        .contextMenu {
            if isFocused {
                Button {
                    focusManager.endFocus()
                } label: {
                    Label("End Focus", systemImage: "scope")
                }
            } else {
                Button {
                    let projectName = appState.projects.first(where: { $0.id == task.projectId })?.title ?? "Inbox"
                    focusManager.switchFocus(task: task, projectName: projectName)
                } label: {
                    Label("Start Focus", systemImage: "scope")
                }
            }
        }
        #endif
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

    private var checkboxColor: Color {
        task.priorityLevel == .none ? .gray : priorityColor
    }
}
