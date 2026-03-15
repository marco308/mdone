import SwiftUI

struct MacKeyboardShortcuts: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var showingQuickAdd = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingQuickAdd) {
                MacQuickAddSheet()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Task")
                }
            }
    }
}

extension View {
    func macKeyboardShortcuts() -> some View {
        modifier(MacKeyboardShortcuts())
    }
}

struct MacQuickAddSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedProjectId: Int64 = 0
    @State private var dueDate: Date? = nil
    @State private var hasDueDate = false
    @State private var priority: Int64 = 0
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task")
                .font(.headline)

            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit {
                    if !title.isEmpty {
                        addTask()
                    }
                }

            if !appState.projects.isEmpty {
                Picker("Project", selection: $selectedProjectId) {
                    ForEach(appState.projects) { project in
                        Text(project.title).tag(project.id)
                    }
                }
            }

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

            Picker("Priority", selection: $priority) {
                ForEach(PriorityLevel.allCases, id: \.rawValue) { level in
                    Text(level.label).tag(Int64(level.rawValue))
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Task") { addTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            selectedProjectId = appState.projects.first?.id ?? 0
            titleFocused = true
        }
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selectedProjectId > 0 else { return }
        Task {
            await appState.createTask(
                title: trimmed,
                projectId: selectedProjectId,
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority
            )
            dismiss()
        }
    }
}
