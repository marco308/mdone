import SwiftUI

/// A Kanban board for a project: one column per bucket, with the tasks in each
/// column shown as cards. Tasks can be moved between columns via a card's
/// context menu. Driven by the project's *kanban* view (`project.kanbanViewId`).
struct ProjectBoardView: View {
    @Environment(AppState.self) private var appState
    let project: Project

    @State private var buckets: [Bucket] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    #if os(iOS)
    private let columnWidth: CGFloat = 280
    #else
    private let columnWidth: CGFloat = 300
    #endif

    var body: some View {
        Group {
            if buckets.isEmpty, hasLoaded, !isLoading {
                EmptyStateView(
                    icon: "rectangle.split.3x1",
                    title: "No columns",
                    subtitle: "This project has no Kanban columns yet"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(buckets) { bucket in
                            BoardColumn(
                                bucket: bucket,
                                otherBuckets: buckets.filter { $0.id != bucket.id },
                                project: project,
                                onChanged: { await reload() }
                            )
                            .frame(width: columnWidth)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .overlay {
            if isLoading, buckets.isEmpty {
                LoadingOverlay()
            }
        }
        .task(id: project.id) {
            await reload()
        }
    }

    private func reload() async {
        if !hasLoaded { isLoading = true }
        buckets = await appState.fetchBuckets(project: project)
        isLoading = false
        hasLoaded = true
    }
}

/// A single board column: a titled header with a task count and its cards.
private struct BoardColumn: View {
    let bucket: Bucket
    let otherBuckets: [Bucket]
    let project: Project
    let onChanged: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            let tasks = bucket.activeTasks
            if tasks.isEmpty {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(tasks) { task in
                            BoardTaskCard(
                                task: task,
                                otherBuckets: otherBuckets,
                                project: project,
                                onChanged: onChanged
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(8)
        .background(columnBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(bucket.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer()

            Text(countText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(bucket.isOverLimit ? .red : .secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.title) column, \(countText) tasks")
    }

    private var countText: String {
        let count = bucket.activeTasks.count
        if bucket.hasLimit, let limit = bucket.limit {
            return "\(count)/\(limit)"
        }
        return "\(count)"
    }

    private var columnBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(.windowBackgroundColor).opacity(0.5)
        #endif
    }
}

/// A compact task card on the board. Opens detail on tap (iOS); offers a "Move
/// to" submenu and a done toggle via its context menu.
private struct BoardTaskCard: View {
    @Environment(AppState.self) private var appState
    let task: VTask
    let otherBuckets: [Bucket]
    let project: Project
    let onChanged: () async -> Void

    @State private var showDetail = false

    var body: some View {
        card
            #if os(iOS)
            .contentShape(Rectangle())
            .onTapGesture { showDetail = true }
            .sheet(isPresented: $showDetail) {
                TaskDetailSheet(task: task)
            }
            #endif
            .contextMenu {
                Button {
                    Task {
                        await appState.toggleTaskDone(task)
                        await onChanged()
                    }
                } label: {
                    Label(task.done ? "Mark Incomplete" : "Mark Done",
                          systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
                }

                if !otherBuckets.isEmpty {
                    Menu {
                        ForEach(otherBuckets) { bucket in
                            Button(bucket.title) {
                                Task {
                                    await appState.moveTask(task, toBucket: bucket.id, in: project)
                                    await onChanged()
                                }
                            }
                        }
                    } label: {
                        Label("Move to", systemImage: "arrow.right.square")
                    }
                }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 4)
                    .accessibilityHidden(true)

                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if task.priority > 0 {
                    PriorityBadge(priority: task.priorityLevel)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if task.effectiveDueDate != nil || (task.labels?.isEmpty == false) {
                HStack(spacing: 8) {
                    if let dueDate = task.effectiveDueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(dueDate, style: .date)
                        }
                        .font(.caption2)
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }

                    if let labels = task.labels, !labels.isEmpty {
                        ForEach(labels.prefix(2)) { label in
                            LabelChip(label: label)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [task.title]
        if task.priority > 0 { parts.append("priority \(task.priorityLevel.label)") }
        if let due = task.effectiveDueDate {
            if task.isOverdue { parts.append("overdue") }
            parts.append("due \(due.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
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

    private var cardBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(.controlBackgroundColor)
        #endif
    }
}
