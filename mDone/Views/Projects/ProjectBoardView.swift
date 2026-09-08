import SwiftUI

/// A Kanban board for a project: one column per bucket, with the tasks in each
/// column shown as cards. Cards can be dragged up and down a column and into
/// another one; a card's context menu also offers "Move to" for columns that
/// are off screen. Driven by the project's *kanban* view (`project.kanbanViewId`).
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

    /// Dragging is off on a board whose columns are filled by filters: the
    /// server has no bucket rows to move a task between there.
    private var canDrag: Bool {
        project.boardAllowsManualPlacement
    }

    var body: some View {
        Group {
            if buckets.isEmpty, hasLoaded, !isLoading {
                EmptyStateView(
                    icon: "rectangle.split.3x1",
                    title: String(localized: "No columns"),
                    subtitle: String(localized: "This project has no Kanban columns yet")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(buckets) { bucket in
                            BoardColumn(
                                bucket: bucket,
                                otherBuckets: buckets.filter { $0.id != bucket.id },
                                project: project,
                                canDrag: canDrag,
                                onChanged: { await reload() },
                                onDrop: { taskId, index in
                                    handleDrop(taskId: taskId, into: bucket, at: index)
                                }
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
        if !hasLoaded {
            isLoading = true
        }
        buckets = await appState.fetchBuckets(project: project)
        isLoading = false
        hasLoaded = true
    }

    /// Lands a dragged card in `bucket` before the card at `index` among the
    /// column's visible cards (`nil` appends). The board updates on the spot
    /// so the card stays put, then the move is sent and the board reloaded so
    /// the server's order wins either way. Returns `false` for a drop that
    /// cannot be placed, which lets the drag animate back.
    @discardableResult
    private func handleDrop(taskId: Int64, into bucket: Bucket, at index: Int?) -> Bool {
        guard canDrag,
              let sourceIndex = buckets.firstIndex(where: { ($0.tasks ?? []).contains { $0.id == taskId } }),
              let task = buckets[sourceIndex].tasks?.first(where: { $0.id == taskId }),
              let targetIndex = buckets.firstIndex(where: { $0.id == bucket.id })
        else { return false }

        let visible = buckets[targetIndex].activeTasks
        let others = visible.filter { $0.id != taskId }
        var insertAt = min(index ?? others.count, others.count)
        if let current = visible.firstIndex(where: { $0.id == taskId }) {
            // Same column: an index counted with the card still in place
            // shifts by one once the card is taken out.
            if current < insertAt {
                insertAt -= 1
            }
            if current == insertAt {
                return true
            }
        }

        let position = TaskPositioning.position(forInserting: task, at: insertAt, into: others)

        var moved = task
        moved.bucketId = bucket.id
        moved.position = position
        buckets[sourceIndex].tasks?.removeAll { $0.id == taskId }
        var targetTasks = buckets[targetIndex].tasks ?? []
        // `tasks` also holds hidden done tasks, so map the visible slot back
        // to a slot in the full array: just before the visible card that
        // now follows, or at the end.
        if insertAt < others.count, let anchor = targetTasks.firstIndex(where: { $0.id == others[insertAt].id }) {
            targetTasks.insert(moved, at: anchor)
        } else {
            targetTasks.append(moved)
        }
        buckets[targetIndex].tasks = targetTasks

        Task {
            await appState.placeTask(task, inBucket: bucket.id, at: position, in: project)
            await reload()
        }
        return true
    }
}

/// What a dragged card carries: its task id behind a prefix, so a stray
/// text drop from elsewhere is ignored rather than parsed as an id.
enum BoardDragPayload {
    private static let prefix = "mdone-task:"

    static func encode(_ taskId: Int64) -> String {
        prefix + String(taskId)
    }

    static func taskId(from items: [String]) -> Int64? {
        for item in items where item.hasPrefix(prefix) {
            if let id = Int64(item.dropFirst(prefix.count)) {
                return id
            }
        }
        return nil
    }
}

/// A single board column: a titled header with a task count and its cards.
private struct BoardColumn: View {
    let bucket: Bucket
    let otherBuckets: [Bucket]
    let project: Project
    let canDrag: Bool
    let onChanged: () async -> Void
    /// Called with the dragged task's id and the visible index to insert
    /// before (`nil` appends). Returns whether the drop was accepted.
    let onDrop: (Int64, Int?) -> Bool

    @State private var isTargeted = false

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
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            BoardTaskCard(
                                task: task,
                                otherBuckets: otherBuckets,
                                project: project,
                                canDrag: canDrag,
                                onChanged: onChanged,
                                onDrop: { taskId, before in
                                    onDrop(taskId, before ? index : index + 1)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(8)
        .background(columnBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        // Dropping on the column itself (its header, the gap below the last
        // card, an empty column) appends. A drop on a card is taken by the
        // card's own destination first.
        .dropDestination(for: String.self) { items, _ in
            guard canDrag, let taskId = BoardDragPayload.taskId(from: items) else { return false }
            return onDrop(taskId, nil)
        } isTargeted: { targeted in
            isTargeted = canDrag && targeted
        }
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
        .accessibilityLabel(String(localized: "\(bucket.title) column, \(countText) tasks"))
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
/// to" submenu and a done toggle via its context menu. Draggable, and a drop
/// target for other cards: the top half of the card means "put it above me",
/// the bottom half "below me".
private struct BoardTaskCard: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    /// Present while the hosting screen shows an inline detail pane (iPad,
    /// regular width); absent, a tap opens the sheet.
    @Environment(InlineTaskSelection.self) private var inlineSelection: InlineTaskSelection?
    #endif
    let task: VTask
    let otherBuckets: [Bucket]
    let project: Project
    let canDrag: Bool
    let onChanged: () async -> Void
    /// Called with the dragged task's id and whether it should land before
    /// (`true`) or after this card.
    let onDrop: (Int64, Bool) -> Bool

    @State private var showDetail = false
    @State private var isTargeted = false
    @State private var height: CGFloat = 0

    var body: some View {
        card
            #if os(iOS)
            .contentShape(Rectangle())
            .onTapGesture {
                if let inlineSelection {
                    inlineSelection.task = task
                } else {
                    showDetail = true
                }
            }
            // Cards lift under a trackpad or mouse pointer on iPad.
            .hoverEffect(.lift)
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
                    Label(
                        task.done ? "Mark Incomplete" : "Mark Done",
                        systemImage: task.done ? "arrow.uturn.backward" : "checkmark"
                    )
                }

                if !otherBuckets.isEmpty {
                    Menu {
                        ForEach(otherBuckets) { bucket in
                            Button(bucket.title) {
                                Task {
                                    if await appState.moveTask(task, toBucket: bucket.id, in: project) {
                                        await onChanged()
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Move to", systemImage: "arrow.right.square")
                    }
                }
            }
            .modifier(BoardDragModifier(task: task, enabled: canDrag))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                height = newHeight
            }
            .dropDestination(for: String.self) { items, location in
                guard canDrag, let taskId = BoardDragPayload.taskId(from: items), taskId != task.id else {
                    return false
                }
                return onDrop(taskId, location.y < height / 2)
            } isTargeted: { targeted in
                isTargeted = canDrag && targeted
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
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        // A comma-separated list of independent facts rather than a sentence,
        // so each fragment is a key of its own.
        var parts = [task.title]
        if task.priority > 0 {
            parts.append(String(localized: "priority \(task.priorityLevel.label)"))
        }
        if let due = task.effectiveDueDate {
            if task.isOverdue {
                parts.append(String(localized: "overdue"))
            }
            parts.append(String(localized: "due \(due.formatted(date: .abbreviated, time: .omitted))"))
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

/// Makes a card draggable, carrying its task id, with a compact title as
/// the drag preview. Applied only while the board allows placement.
private struct BoardDragModifier: ViewModifier {
    let task: VTask
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(BoardDragPayload.encode(task.id)) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .padding(10)
                    .frame(width: 240, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            content
        }
    }
}
