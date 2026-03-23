import SwiftUI

struct TaskFilterSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPriority: PriorityLevel? = nil
    @State private var selectedDateRange: DateRangeOption = .any
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date().addingTimeInterval(7.0 * 24.0 * 3600.0)
    @State private var doneFilter: DoneFilter = .undone
    @State private var selectedProjectId: Int64? = nil

    var onApply: (String?) -> Void

    enum DateRangeOption: String, CaseIterable {
        case any = "Any"
        case overdue = "Overdue"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case custom = "Custom Range"
    }

    enum DoneFilter: String, CaseIterable {
        case any = "Any"
        case done = "Done"
        case undone = "Undone"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Priority") {
                    Picker("Priority", selection: $selectedPriority) {
                        Text("Any").tag(PriorityLevel?.none)
                        ForEach(PriorityLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(PriorityLevel?.some(level))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Due Date") {
                    Picker("Date Range", selection: $selectedDateRange) {
                        ForEach(DateRangeOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedDateRange == .custom {
                        DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                    }
                }

                Section("Status") {
                    Picker("Completion", selection: $doneFilter) {
                        ForEach(DoneFilter.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Project") {
                    Picker("Project", selection: $selectedProjectId) {
                        Text("Any").tag(Int64?.none)
                        ForEach(appState.projects) { project in
                            Text(project.title).tag(Int64?.some(project.id))
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
                        resetFilters()
                        onApply(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(buildFilterString())
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func resetFilters() {
        selectedPriority = nil
        selectedDateRange = .any
        customStartDate = Date()
        customEndDate = Date().addingTimeInterval(7 * 24 * 3600)
        doneFilter = .undone
        selectedProjectId = nil
    }

    private func buildFilterString() -> String? {
        var parts: [String] = []

        if let selectedPriority, selectedPriority != .none {
            parts.append("priority = \(selectedPriority.rawValue)")
        }

        switch selectedDateRange {
        case .any:
            break
        case .overdue:
            parts.append("due_date < now")
        case .today:
            parts.append("due_date > now-1d && due_date < now+1d")
        case .thisWeek:
            parts.append("due_date > now && due_date < now+7d")
        case .thisMonth:
            parts.append("due_date > now && due_date < now+30d")
        case .custom:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let start = formatter.string(from: customStartDate)
            let end = formatter.string(from: customEndDate)
            parts.append("due_date > \"\(start)\" && due_date < \"\(end)\"")
        }

        switch doneFilter {
        case .any:
            break
        case .done:
            parts.append("done = true")
        case .undone:
            parts.append("done = false")
        }

        if let selectedProjectId {
            parts.append("project_id = \(selectedProjectId)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " && ")
    }
}
