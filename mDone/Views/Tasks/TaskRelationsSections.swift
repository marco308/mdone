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
    @State private var showLinkSheet = false

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

            Button {
                showLinkSheet = true
            } label: {
                Label("Link Existing Task…", systemImage: "link")
            }
            .sheet(isPresented: $showLinkSheet) {
                LinkSubtaskSheet(parent: liveTask)
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
        } footer: {
            Text("Subtasks nest under this task in your lists. Unlinking never deletes a task.")
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

}

/// Full-screen-friendly picker for turning an existing task into a subtask of
/// `parent`. Lists every eligible open task across all projects (Vikunja
/// supports cross-project relations), the parent's own project first, with a
/// search field and each task's project shown underneath its title.
struct LinkSubtaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let parent: VTask

    @State private var searchText = ""
    @State private var isLinking = false

    private var candidates: [VTask] {
        let all = SubtaskLinkCandidates.candidates(for: parent, in: appState.tasks)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    EmptyStateView(
                        icon: "link",
                        title: searchText.isEmpty ? "No Tasks to Link" : "No Matches",
                        subtitle: searchText.isEmpty
                            ? "Every other open task is already related to this one."
                            : "No open task titles match your search."
                    )
                } else {
                    List {
                        Section {
                            ForEach(candidates) { candidate in
                                candidateRow(for: candidate)
                            }
                        } header: {
                            Text("The task you pick becomes a subtask of \"\(parent.title)\". It stays in its own project.")
                                .textCase(nil)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tasks")
            .navigationTitle("Link Subtask")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
    }

    private func candidateRow(for candidate: VTask) -> some View {
        Button {
            guard !isLinking else { return }
            isLinking = true
            Task {
                let linked = await appState.addSubtaskRelation(parentId: parent.id, childId: candidate.id)
                isLinking = false
                if linked { dismiss() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .foregroundStyle(Color.primary)
                Text(projectName(for: candidate))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(isLinking)
        .accessibilityLabel("Link \(candidate.title) as subtask")
    }

    private func projectName(for task: VTask) -> String {
        appState.projects.first(where: { $0.id == task.projectId })?.title ?? "Project \(task.projectId)"
    }
}
