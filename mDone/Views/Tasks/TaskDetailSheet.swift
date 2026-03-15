import SwiftUI

struct TaskDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let task: VTask

    @State private var title: String
    @State private var description: String
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var priority: Int64
    @State private var selectedProjectId: Int64
    @State private var showDeleteConfirm = false

    init(task: VTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _dueDate = State(initialValue: task.dueDate)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _priority = State(initialValue: task.priority)
        _selectedProjectId = State(initialValue: task.projectId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                        .font(.headline)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                }

                Section {
                    Toggle("Due Date", isOn: $hasDueDate.animation())

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
                    Button("Delete Task", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTask() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty)
                }
            }
            .alert("Delete Task?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await appState.deleteTask(task)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveTask() {
        let request = TaskUpdateRequest(
            title: title,
            description: description.isEmpty ? nil : description,
            dueDate: hasDueDate ? (dueDate ?? Date()) : nil,
            priority: priority,
            projectId: selectedProjectId
        )
        Task {
            await appState.updateTask(id: task.id, request: request)
            dismiss()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = layout(sizes: sizes, containerWidth: bounds.width).positions

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if x + size.width > containerWidth && x > 0 {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxHeight = max(maxHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (positions, CGSize(width: maxWidth, height: y + maxHeight))
    }
}
