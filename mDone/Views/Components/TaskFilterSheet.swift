import SwiftUI

struct TaskFilterSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// A working copy of the applied filter. Seeded from it, so reopening the
    /// sheet shows what is in effect rather than the defaults; only Apply or
    /// Reset hands a value back.
    @State private var draft: AdvancedTaskFilter

    private let onApply: (AdvancedTaskFilter) -> Void

    init(filter: AdvancedTaskFilter, onApply: @escaping (AdvancedTaskFilter) -> Void) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        Text("Any").tag(PriorityLevel?.none)
                        ForEach(PriorityLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(PriorityLevel?.some(level))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Due Date") {
                    Picker("Date Range", selection: $draft.dateRange) {
                        ForEach(AdvancedTaskFilter.DateRange.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    if draft.dateRange == .custom {
                        DatePicker("From", selection: $draft.customStart, displayedComponents: .date)
                        DatePicker("To", selection: $draft.customEnd, displayedComponents: .date)
                    }
                }

                Section("Status") {
                    Picker("Completion", selection: $draft.status) {
                        ForEach(AdvancedTaskFilter.Status.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Project") {
                    Picker("Project", selection: $draft.projectId) {
                        Text("Any").tag(Int64?.none)
                        ForEach(appState.projects.projectHierarchy().flattened { _ in true }) { row in
                            Text(String(repeating: "  ", count: row.depth) + row.project.title)
                                .tag(Int64?.some(row.project.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Advanced Filter")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") {
                            onApply(AdvancedTaskFilter())
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            onApply(draft)
                            dismiss()
                        }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
