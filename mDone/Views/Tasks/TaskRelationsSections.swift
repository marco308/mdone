import SwiftUI

/// The Subtasks / Parent Task / Related Tasks sections shared by the iOS
/// detail sheet and the macOS detail view. Reads the live copy of the task
/// from `AppState` (the passed-in value is a snapshot from when the detail
/// view opened) so relation edits show up immediately.
struct TaskRelationsSections: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    @State private var newSubtaskTitle = ""
    @State private var isAddingSubtask = false

    /// The freshest copy of the task we can get: live from AppState when
    /// loaded, else the snapshot the detail view was opened with.
    private var liveTask: VTask {
        appState.tasks.first(where: { $0.id == task.id }) ?? task
    }

    var body: some View {
        subtasksSection
        if liveTask.hasParentTask {
            parentSection
        }
        if !otherRelationEntries.isEmpty {
            otherRelationsSection
        }
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        Section {
            ForEach(liveTask.subtasks) { subtask in
                subtaskRow(for: live(subtask))
            }

            HStack {
                TextField("Add subtask", text: $newSubtaskTitle)
                    .onSubmit(addNewSubtask)
                Button(action: addNewSubtask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(trimmedNewTitle.isEmpty || isAddingSubtask)
                .accessibilityLabel("Add subtask")
            }

            if !linkCandidates.isEmpty {
                Menu {
                    ForEach(linkCandidates) { candidate in
                        Button(candidate.title) {
                            Task {
                                await appState.addSubtaskRelation(parentId: liveTask.id, childId: candidate.id)
                            }
                        }
                    }
                } label: {
                    Label("Link Existing Task", systemImage: "link")
                }
            }
        } header: {
            HStack {
                Text("Subtasks")
                Spacer()
                if let counts = liveTask.subtaskCounts {
                    Text("\(counts.done)/\(counts.total) done")
                        .monospacedDigit()
                }
            }
        }
    }

    private func subtaskRow(for subtask: VTask) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await appState.toggleTaskDone(subtask) }
            } label: {
                Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.done ? .green : .gray)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                subtask.done ? "Mark \(subtask.title) as incomplete" : "Mark \(subtask.title) as complete"
            )
            .accessibilityAddTraits(.isToggle)

            Text(subtask.title)
                .strikethrough(subtask.done)
                .foregroundStyle(subtask.done ? .secondary : .primary)

            Spacer()

            unlinkButton(otherTaskId: subtask.id, kind: .subtask, title: subtask.title)
        }
    }

    // MARK: - Parent

    private var parentSection: some View {
        Section("Parent Task") {
            ForEach(liveTask.parentTasks) { parent in
                let parentTask = live(parent)
                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(parentTask.title)
                        .strikethrough(parentTask.done)
                    Spacer()
                    unlinkButton(otherTaskId: parent.id, kind: .parenttask, title: parentTask.title)
                }
            }
        }
    }

    // MARK: - Other relation kinds

    /// Relations other than subtask/parenttask (blocking, related, …), one
    /// entry per (kind, task) pair. Unknown kinds a newer server might send
    /// still display; they just can't be unlinked from mDone.
    private struct RelationEntry: Identifiable {
        let rawKind: String
        let task: VTask
        var id: String {
            "\(rawKind)-\(task.id)"
        }

        var kind: RelationKind? {
            RelationKind(rawValue: rawKind)
        }
    }

    private var otherRelationEntries: [RelationEntry] {
        guard let related = liveTask.relatedTasks else { return [] }
        return related
            .filter { $0.key != RelationKind.subtask.rawValue && $0.key != RelationKind.parenttask.rawValue }
            .sorted { $0.key < $1.key }
            .flatMap { kind, tasks in tasks.map { RelationEntry(rawKind: kind, task: $0) } }
    }

    private var otherRelationsSection: some View {
        Section("Related Tasks") {
            ForEach(otherRelationEntries) { entry in
                let relatedTask = live(entry.task)
                HStack(spacing: 12) {
                    Text(RelationKind.label(forRawKind: entry.rawKind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    Text(relatedTask.title)
                        .strikethrough(relatedTask.done)
                    Spacer()
                    if let kind = entry.kind {
                        unlinkButton(otherTaskId: entry.task.id, kind: kind, title: relatedTask.title)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func unlinkButton(otherTaskId: Int64, kind: RelationKind, title: String) -> some View {
        Button {
            Task {
                await appState.removeRelation(taskId: liveTask.id, otherTaskId: otherTaskId, kind: kind)
            }
        } label: {
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove \(kind.label.lowercased()) relation to \(title)")
    }

    private func live(_ snapshot: VTask) -> VTask {
        appState.tasks.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    private var trimmedNewTitle: String {
        newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addNewSubtask() {
        let title = trimmedNewTitle
        guard !title.isEmpty, !isAddingSubtask else { return }
        isAddingSubtask = true
        Task {
            if await appState.createSubtask(title: title, parent: liveTask) {
                newSubtaskTitle = ""
            }
            isAddingSubtask = false
        }
    }

    /// Same-project tasks that could become subtasks of this one: not done,
    /// not itself, not already a subtask, and not one of its parents (which
    /// would create an immediate cycle). Capped to keep the menu usable.
    private var linkCandidates: [VTask] {
        let current = liveTask
        let subtaskIds = Set(current.subtasks.map(\.id))
        let parentIds = Set(current.parentTasks.map(\.id))
        return appState.tasks
            .filter {
                $0.projectId == current.projectId
                    && !$0.done
                    && $0.id != current.id
                    && !subtaskIds.contains($0.id)
                    && !parentIds.contains($0.id)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            .prefix(30)
            .map { $0 }
    }
}
