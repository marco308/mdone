import SwiftUI

struct TaskRow: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    let task: VTask
    /// When true, the row is display-only: no completion toggle, swipe actions,
    /// context menu, or tap-to-edit. Used for archived (read-only) projects.
    var readOnly: Bool = false
    /// When true, the row shows a progress bar and (when stalled) an idle badge.
    /// Used by the "Current" section.
    var showsProgress: Bool = false
    @State private var showDetail = false
    @AppStorage("calmMode") private var calmMode = false
    @AppStorage("currentStallDays") private var stallDays = 7

    /// Quick-set progress percentages offered in the context menu.
    private static let progressSteps = [0, 25, 50, 75, 100]

    #if os(iOS)
    private var isFocused: Bool {
        focusManager.focusedTaskId == task.id
    }
    #endif

    private var isProjected: Bool {
        task.id < 0
    }

    var body: some View {
        rowContent
        #if os(iOS)
        .contentShape(Rectangle())
        .onTapGesture { if !readOnly { showDetail = true } }
        .listRowBackground(isFocused ? Color.orange.opacity(0.08) : nil)
        #endif
        .swipeActions(edge: .leading) {
            if !readOnly {
                #if os(iOS)
                if !task.done && !isProjected {
                    Button {
                        Task { await appState.postponeTask(task, byHours: 24) }
                    } label: {
                        Label("+24h", systemImage: "clock.arrow.circlepath")
                    }
                    .tint(.blue)
                }

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

                if !isProjected {
                    Button {
                        Task { await appState.toggleTaskDone(task) }
                    } label: {
                        Label(task.done ? "Undo" : "Done", systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(.green)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !readOnly && !isProjected {
                Button(role: .destructive) {
                    Task { await appState.deleteTask(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if !readOnly {
                if !task.done && !isProjected {
                    Menu {
                        ForEach(QuickSchedule.options()) { option in
                            Button {
                                guard let date = option.resolvedDate() else { return }
                                Task { await appState.rescheduleTask(task, to: date) }
                            } label: {
                                Label(option.label, systemImage: option.systemImage)
                            }
                        }
                    } label: {
                        Label("Schedule", systemImage: "calendar")
                    }
                }

                #if os(iOS)
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
                #endif

                if !isProjected {
                    Button {
                        Task { await appState.toggleCurrent(task) }
                    } label: {
                        Label(
                            appState.isCurrent(task) ? "Remove from Current" : "Mark as Current",
                            systemImage: appState.isCurrent(task) ? "pin.slash" : "pin"
                        )
                    }
                }

                if appState.isCurrent(task) {
                    Menu {
                        ForEach(Self.progressSteps, id: \.self) { pct in
                            Button("\(pct)%") {
                                Task { await appState.setProgress(task, percent: Double(pct) / 100) }
                            }
                        }
                    } label: {
                        Label("Set Progress", systemImage: "chart.bar")
                    }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task)
        }
        #endif
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            if isProjected {
                Image(systemName: "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Future projection")
                    .padding(.top, 2) // alignment
            } else {
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
                .disabled(readOnly)
                .accessibilityLabel(task.done ? "Mark \(task.title) as incomplete" : "Mark \(task.title) as complete")
                .accessibilityAddTraits(.isToggle)
            }

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
                            if task.hasSpecificTime {
                                Text(dueDate, format: .dateTime.month().day().year().hour().minute())
                            } else {
                                Text(dueDate, style: .date)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(task.isOverdue && !calmMode ? .red : .secondary)
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

                if showsProgress {
                    CurrentProgressIndicator(percent: task.percentDone ?? 0, stalledDays: stalledDays)
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
                    .accessibilityLabel("Focused")
            }
            #endif
        }
        .padding(.vertical, 4)
        .opacity(task.done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel)
    }

    private var taskAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(task.title)
        if task.done {
            parts.append("completed")
        }
        if task.priority > 0 {
            parts.append("priority \(task.priorityLevel.label)")
        }
        if let dueDate = task.effectiveDueDate {
            if task.isOverdue {
                parts.append("overdue")
            }
            parts.append("due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if task.isRepeating, let desc = task.repeatDescription {
            parts.append("repeats \(desc)")
        }
        if let labels = task.labels, !labels.isEmpty {
            let labelNames = labels.prefix(3).map(\.title).joined(separator: ", ")
            parts.append("labels: \(labelNames)")
        }
        return parts.joined(separator: ", ")
    }

    /// Days since the task was last touched, but only once it exceeds the
    /// configured stall threshold, so the idle badge appears only for tasks
    /// that have genuinely gone quiet. `nil` otherwise.
    private var stalledDays: Int? {
        guard let updated = task.updated else { return nil }
        let days = Calendar.current.dateComponents([.day], from: updated, to: Date()).day ?? 0
        return days >= stallDays ? days : nil
    }

    /// The task's own Vikunja color, when set. `nil` for uncolored tasks.
    private var taskColor: Color? {
        task.normalizedHexColor.map { Color(hex: $0) }
    }

    /// The leading accent bar prefers the user-assigned task color, falling
    /// back to the priority color (which is also shown as a badge) so the bar
    /// keeps signalling priority for uncolored tasks.
    private var accentColor: Color {
        taskColor ?? priorityColor
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
        if let taskColor { return taskColor }
        return task.priorityLevel == .none ? .gray : priorityColor
    }
}

/// A thin progress bar with a percentage and, when the task has gone idle past
/// the stall threshold, an "Idle Nd" badge. Shown on rows in the Current section.
struct CurrentProgressIndicator: View {
    let percent: Double
    let stalledDays: Int?

    private var percentText: String {
        "\(Int((percent * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: min(max(percent, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text(percentText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let stalledDays {
                Label("Idle \(stalledDays)d", systemImage: "zzz")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(Int((percent * 100).rounded())) percent complete"]
        if let stalledDays {
            parts.append("idle \(stalledDays) days")
        }
        return parts.joined(separator: ", ")
    }
}
