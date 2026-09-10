import SwiftUI

/// The Labels section of a task's detail view: the labels the task carries,
/// read live from `AppState`, and a button that opens the picker. Shared by
/// the iOS sheet, the iPad pane and the macOS detail view (issue #4).
struct TaskLabelsSection: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    @State private var isPickingLabels = false

    /// The live copy wins over the snapshot the detail view was opened with,
    /// so a change made in the picker shows here as soon as it is made.
    private var labels: [VLabel] {
        (appState.tasks.first(where: { $0.id == task.id }) ?? task).labels ?? []
    }

    var body: some View {
        Section("Labels") {
            if !labels.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(labels) { label in
                        LabelChip(label: label)
                    }
                }
            }
            Button {
                isPickingLabels = true
            } label: {
                if labels.isEmpty {
                    Label("Add Labels", systemImage: "tag")
                } else {
                    Label("Edit Labels", systemImage: "tag")
                }
            }
            .sheet(isPresented: $isPickingLabels) {
                LabelPickerSheet(task: task)
            }
        }
    }
}

/// Turns labels on and off for one task, and creates new ones. Every change
/// is applied the moment it is made, through the dedicated label endpoints,
/// because Vikunja does not accept labels on the task-update call. There is
/// nothing to save: Done just closes the sheet.
struct LabelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let task: VTask

    /// Filters the list, and doubles as the title of a label to create.
    @State private var query = ""
    @State private var newLabelColor = ""
    @State private var isCreating = false
    /// Labels whose toggle is in flight, so a double tap can't race itself.
    @State private var busyLabelIds: Set<Int64> = []
    @FocusState private var queryFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedLabels: [VLabel] {
        appState.labels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleLabels: [VLabel] {
        guard !trimmedQuery.isEmpty else { return sortedLabels }
        return sortedLabels.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// True when the typed title matches no existing label exactly, so
    /// creating one would not make a duplicate.
    private var canCreate: Bool {
        guard !trimmedQuery.isEmpty, !isCreating else { return false }
        return !appState.labels.contains { $0.title.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Search or add a label", text: $query)
                        .focused($queryFocused)
                        .autocorrectionDisabled()
                        .onSubmit {
                            if canCreate {
                                createLabel()
                            }
                        }
                    if canCreate {
                        ColorSwatchPicker(selectedHex: $newLabelColor)
                        Button {
                            createLabel()
                        } label: {
                            Label("Create \"\(trimmedQuery)\"", systemImage: "plus.circle")
                        }
                    }
                }

                Section {
                    if visibleLabels.isEmpty {
                        if appState.labels.isEmpty {
                            Text("No labels yet. Type a name above to create one.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No labels match.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(visibleLabels) { label in
                        labelRow(label)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Labels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { queryFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    private func labelRow(_ label: VLabel) -> some View {
        let applied = appState.hasLabel(label, on: task)
        return Button {
            toggle(label)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(label.color)
                    .frame(width: 12, height: 12)
                Text(label.title)
                    .foregroundStyle(.primary)
                Spacer()
                if applied {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyLabelIds.contains(label.id))
        .accessibilityLabel(label.title)
        .accessibilityAddTraits(applied ? .isSelected : [])
    }

    private func toggle(_ label: VLabel) {
        busyLabelIds.insert(label.id)
        Task { @MainActor in
            await appState.toggleLabel(label, on: task)
            busyLabelIds.remove(label.id)
        }
    }

    /// Creates the typed label and puts it straight on the task: someone who
    /// types a new name here wants it applied, not just to exist.
    private func createLabel() {
        guard canCreate else { return }
        isCreating = true
        let title = trimmedQuery
        let color = newLabelColor
        Task { @MainActor in
            if let created = await appState.createLabel(title: title, hexColor: color) {
                await appState.toggleLabel(created, on: task)
                query = ""
                newLabelColor = ""
            }
            isCreating = false
        }
    }
}
