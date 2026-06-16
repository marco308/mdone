import SwiftUI

struct MacTaskDetailView: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    @State private var title: String
    @State private var descriptionText: String
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var priority: Int64
    @State private var selectedProjectId: Int64
    @State private var repeatInterval: Int64
    @State private var reminders: [TaskReminder]
    @State private var showDeleteConfirm = false
    @State private var isShowingDescriptionPreview: Bool
    @State private var estimateSeconds: TimeInterval?
    @State private var percentDone: Double

    init(task: VTask) {
        self.task = task
        let initialDescription = task.userVisibleDescription ?? ""
        _title = State(initialValue: task.title)
        _descriptionText = State(initialValue: initialDescription)
        _dueDate = State(initialValue: task.dueDate)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _priority = State(initialValue: task.priority)
        _selectedProjectId = State(initialValue: task.projectId)
        _repeatInterval = State(initialValue: task.repeatAfter ?? 0)
        _reminders = State(initialValue: task.reminders ?? [])
        _isShowingDescriptionPreview = State(initialValue: !initialDescription.isEmpty)
        _estimateSeconds = State(initialValue: task.estimatedSeconds)
        _percentDone = State(initialValue: task.percentDone ?? 0)
    }

    /// The live "Current" state from `AppState`, so the toggle label reflects
    /// changes made while the detail view is open.
    private var isCurrentNow: Bool {
        appState.isCurrent(appState.tasks.first(where: { $0.id == task.id }) ?? task)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Task title", text: $title)
                    .font(.title3)
                    .textFieldStyle(.plain)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            isShowingDescriptionPreview.toggle()
                        } label: {
                            Image(systemName: isShowingDescriptionPreview ? "pencil" : "eye")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help(isShowingDescriptionPreview ? "Edit" : "Preview description")
                        .accessibilityLabel(isShowingDescriptionPreview ? "Edit description" : "Preview description")
                    }

                    if isShowingDescriptionPreview {
                        if descriptionText.isEmpty {
                            Text("No description")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                                .frame(minHeight: 100, alignment: .topLeading)
                        } else {
                            ScrollView {
                                Text(RichTextRenderer.render(descriptionText))
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(minHeight: 100, maxHeight: 200)
                        }
                    } else {
                        TextEditor(text: $descriptionText)
                            .font(.body)
                            .frame(minHeight: 100, maxHeight: 200)
                            .scrollContentBackground(.hidden)
                    }
                }
            }

            Section("Current") {
                Button {
                    Task { await appState.toggleCurrent(task) }
                } label: {
                    Label(
                        isCurrentNow ? "Remove from Current" : "Mark as Current",
                        systemImage: isCurrentNow ? "pin.slash" : "pin"
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress")
                        Spacer()
                        Text("\(Int((percentDone * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $percentDone, in: 0 ... 1, step: 0.05)
                        .accessibilityLabel("Progress")
                        .accessibilityValue("\(Int((percentDone * 100).rounded())) percent")
                }
            }

            Section("Due Date") {
                Toggle("Has due date", isOn: $hasDueDate.animation())

                if hasDueDate {
                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section {
                EstimatePicker(estimateSeconds: $estimateSeconds)
            }

            Section("Repeat") {
                Picker("Repeat", selection: $repeatInterval) {
                    Text("Never").tag(Int64(0))
                    Text("Daily").tag(Int64(86400))
                    Text("Weekly").tag(Int64(604_800))
                    Text("Every 2 Weeks").tag(Int64(1_209_600))
                    Text("Monthly").tag(Int64(2_592_000))
                    Text("Yearly").tag(Int64(31_536_000))
                }
            }

            Section("Reminders") {
                ReminderEditor(reminders: $reminders)
            }

            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(PriorityLevel.allCases, id: \.rawValue) { level in
                        HStack {
                            PriorityBadge(priority: level)
                            Text(level.label)
                        }
                        .tag(Int64(level.rawValue))
                    }
                }
                .pickerStyle(.menu)
            }

            if !appState.projects.isEmpty {
                Section("Project") {
                    Picker("Project", selection: $selectedProjectId) {
                        ForEach(appState.projects) { project in
                            Text(project.title).tag(project.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let labels = task.labels, !labels.isEmpty {
                Section("Labels") {
                    FlowLayout(spacing: 8) {
                        ForEach(labels) { label in
                            LabelChip(label: label)
                        }
                    }
                }
            }

            FocusHistoryGate(taskId: task.id) {
                Section("Focus") {
                    FocusHistoryRow(taskId: task.id)
                }
            }

            Section {
                HStack(spacing: 16) {
                    Button {
                        Task { await appState.toggleTaskDone(task) }
                    } label: {
                        Label(
                            task.done ? "Mark Undone" : "Mark Done",
                            systemImage: task.done ? "arrow.uturn.backward.circle" : "checkmark.circle"
                        )
                    }
                    .keyboardShortcut("d", modifiers: .command)

                    Spacer()

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(task.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { saveTask() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(title.isEmpty)
            }
        }
        .alert("Delete Task?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await appState.deleteTask(task) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: task) { _, newTask in
            title = newTask.title
            let newDescription = newTask.userVisibleDescription ?? ""
            descriptionText = newDescription
            dueDate = newTask.dueDate
            hasDueDate = newTask.dueDate != nil
            priority = newTask.priority
            selectedProjectId = newTask.projectId
            repeatInterval = newTask.repeatAfter ?? 0
            reminders = newTask.reminders ?? []
            isShowingDescriptionPreview = !newDescription.isEmpty
            estimateSeconds = newTask.estimatedSeconds
            percentDone = newTask.percentDone ?? 0
        }
    }

    private func saveTask() {
        let body = descriptionText.isEmpty ? nil : descriptionText
        let composedDescription = EstimateMarker.apply(estimateSeconds, to: body)
        let request = TaskUpdateRequest(
            title: title,
            description: composedDescription,
            dueDate: hasDueDate ? (dueDate ?? Date()) : nil,
            priority: priority,
            projectId: selectedProjectId,
            repeatAfter: repeatInterval,
            reminders: reminders,
            percentDone: percentDone,
            clearDueDate: !hasDueDate
        )
        Task {
            await appState.updateTask(id: task.id, request: request)
        }
    }
}
