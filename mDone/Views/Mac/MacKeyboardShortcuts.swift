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
    /// The values the last parse wrote. A control that no longer holds what
    /// the parser put there was changed by the user, and later parses leave
    /// it alone.
    @State private var appliedProjectId: Int64?
    @State private var appliedDueDate: Date?
    @State private var appliedPriority: Int64?

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

    /// Debounced like the iOS bar, then applied to the controls.
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
            let result = makeParser().parse(rawTitle)
            parse = result
            apply(result)
        }
    }

    private func makeParser() -> SmartTaskParser {
        SmartTaskParser(projects: appState.projects, labels: appState.labels)
    }

    /// Writes the parse into the controls and answers what the task would be
    /// created with. A field the user has changed by hand is left as they set
    /// it: their choice beats every later parse.
    @discardableResult
    private func apply(_ parse: SmartTaskParse) -> (projectId: Int64, dueDate: Date?, priority: Int64) {
        if let due = parse.dueDate, appliedDueDate == nil || (hasDueDate && dueDate == appliedDueDate) {
            hasDueDate = true
            dueDate = due
            appliedDueDate = due
        }
        if let projectId = parse.projectId,
           appState.projects.contains(where: { $0.id == projectId && $0.id > 0 }),
           appliedProjectId == nil || selectedProjectId == appliedProjectId
        {
            selectedProjectId = projectId
            appliedProjectId = projectId
        }
        if let parsed = parse.priority.map(Int64.init), appliedPriority == nil || priority == appliedPriority {
            priority = parsed
            appliedPriority = parsed
        }
        return (selectedProjectId, hasDueDate ? dueDate : nil, priority)
    }

    private func addTask() {
        // Parse what is in the field right now rather than trusting the
        // debounce, so pressing Add mid-keystroke still strips the magic text
        // and keeps the labels, as the iOS bar does.
        var currentParse: SmartTaskParse?
        var values = (projectId: selectedProjectId, dueDate: hasDueDate ? dueDate : nil, priority: priority)
        if smartParsing, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fresh = parse?.text == title ? parse : makeParser().parse(title)
            currentParse = fresh
            if let fresh {
                values = apply(fresh)
            }
        }
        let trimmed = (currentParse?.title ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, values.projectId > 0 else { return }
        parseTask?.cancel()
        parseTask = nil
        Task {
            await appState.createTask(
                title: trimmed,
                projectId: values.projectId,
                dueDate: values.dueDate,
                priority: values.priority,
                labelIds: currentParse?.labelIds ?? []
            )
            dismiss()
        }
    }
}
