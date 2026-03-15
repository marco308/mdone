import SwiftUI

struct ReminderEditor: View {
    @Binding var reminders: [TaskReminder]
    @State private var showAddSheet = false
    @State private var customDate = Date()
    @State private var showCustomPicker = false

    private enum PresetReminder: String, CaseIterable {
        case atDue = "At time of due date"
        case fiveMin = "5 minutes before"
        case fifteenMin = "15 minutes before"
        case thirtyMin = "30 minutes before"
        case oneHour = "1 hour before"
        case oneDay = "1 day before"

        var relativePeriod: Int64 {
            switch self {
            case .atDue: return 0
            case .fiveMin: return -300
            case .fifteenMin: return -900
            case .thirtyMin: return -1800
            case .oneHour: return -3600
            case .oneDay: return -86400
            }
        }

        func toReminder() -> TaskReminder {
            TaskReminder(
                reminder: nil,
                relativePeriod: relativePeriod,
                relativeTo: "due_date"
            )
        }
    }

    var body: some View {
        ForEach(Array(reminders.enumerated()), id: \.offset) { index, reminder in
            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                Text(displayText(for: reminder))
                Spacer()
                Button {
                    reminders.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }

        Button {
            showAddSheet = true
        } label: {
            Label("Add Reminder", systemImage: "plus.circle")
        }
        .confirmationDialog("Add Reminder", isPresented: $showAddSheet) {
            ForEach(PresetReminder.allCases, id: \.self) { preset in
                Button(preset.rawValue) {
                    reminders.append(preset.toReminder())
                }
            }
            Button("Custom date...") {
                showCustomPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCustomPicker) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Reminder Date",
                        selection: $customDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle("Custom Reminder")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            reminders.append(TaskReminder(
                                reminder: customDate,
                                relativePeriod: nil,
                                relativeTo: nil
                            ))
                            showCustomPicker = false
                        }
                    }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium])
            #endif
        }
    }

    private func displayText(for reminder: TaskReminder) -> String {
        if let period = reminder.relativePeriod {
            if period == 0 {
                return "At time of due date"
            }
            let absPeriod = abs(period)
            if absPeriod < 3600 {
                let minutes = absPeriod / 60
                return "\(minutes) min before due"
            } else if absPeriod < 86400 {
                let hours = absPeriod / 3600
                return hours == 1 ? "1 hour before due" : "\(hours) hours before due"
            } else {
                let days = absPeriod / 86400
                return days == 1 ? "1 day before due" : "\(days) days before due"
            }
        } else if let date = reminder.reminder {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Reminder"
    }
}
