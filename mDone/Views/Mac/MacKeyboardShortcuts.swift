import SwiftUI

struct MacKeyboardShortcuts: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var showingQuickAdd = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingQuickAdd) {
                MacQuickAddSheet()
            }
            .onChange(of: appState.quickAddTrigger) { _, newValue in
                // Set by QuickAddIntent when the "Quick Add Task" Shortcuts
                // action runs. Consume it so a later trigger fires again.
                guard newValue != nil else { return }
                appState.quickAddTrigger = nil
                showingQuickAdd = true
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

    /// Smart parsing (#215). Off by default. When on, typing fills the
    /// pickers below rather than adding controls of its own, so the user
    /// sees the result before pressing Add.
    @AppStorage(SmartParsingPreference.storageKey) private var smartParsing = SmartParsingPreference.defaultValue
    @State private var parse: SmartTaskParse?
    @State private var parseTask: Task<Void, Never>?

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
                .onChange(of: title) { _, newValue in
                    scheduleParse(for: newValue)
                }
                .onChange(of: smartParsing) { _, _ in
                    scheduleParse(for: title)
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
            selectedProjectId = appState.defaultProject?.id ?? 0
            titleFocused = true
        }
    }

    /// Debounced like the iOS bar, then applied to the controls. The user's
    /// own picker changes win: a later parse only writes a field the text
    /// actually names.
    private func scheduleParse(for rawTitle: String) {
        parseTask?.cancel()
        guard smartParsing, !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parse = nil
            return
        }
        parseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled {
                return
            }
            let result = SmartTaskParser(projects: appState.projects, labels: appState.labels).parse(rawTitle)
            parse = result
            apply(result)
        }
    }

    private func apply(_ parse: SmartTaskParse) {
        if let due = parse.dueDate {
            hasDueDate = true
            dueDate = due
        }
        if let projectId = parse.projectId, appState.projects.contains(where: { $0.id == projectId }) {
            selectedProjectId = projectId
        }
        if let parsed = parse.priority {
            priority = Int64(parsed)
        }
    }

    private func addTask() {
        // The controls hold the values (the parse filled them, the user may
        // have changed them); only the title and the labels come from the
        // parse itself.
        let currentParse = smartParsing ? parse.flatMap { $0.text == title ? $0 : nil } : nil
        let trimmed = (currentParse?.title ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selectedProjectId > 0 else { return }
        parseTask?.cancel()
        parseTask = nil
        Task {
            await appState.createTask(
                title: trimmed,
                projectId: selectedProjectId,
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority,
                labelIds: currentParse?.labelIds ?? []
            )
            dismiss()
        }
    }
}
