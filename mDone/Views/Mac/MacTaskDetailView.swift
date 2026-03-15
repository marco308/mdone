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
    @State private var showDeleteConfirm = false

    init(task: VTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _descriptionText = State(initialValue: task.description ?? "")
        _dueDate = State(initialValue: task.dueDate)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _priority = State(initialValue: task.priority)
        _selectedProjectId = State(initialValue: task.projectId)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Task title", text: $title)
                    .font(.title3)
                    .textFieldStyle(.plain)
            }

            Section("Description") {
                TextEditor(text: $descriptionText)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 200)
                    .scrollContentBackground(.hidden)
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
            descriptionText = newTask.description ?? ""
            dueDate = newTask.dueDate
            hasDueDate = newTask.dueDate != nil
            priority = newTask.priority
            selectedProjectId = newTask.projectId
        }
    }

    private func saveTask() {
        let request = TaskUpdateRequest(
            title: title,
            description: descriptionText.isEmpty ? nil : descriptionText,
            dueDate: hasDueDate ? (dueDate ?? Date()) : nil,
            priority: priority,
            projectId: selectedProjectId
        )
        Task {
            await appState.updateTask(id: task.id, request: request)
        }
    }
}
