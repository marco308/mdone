import SwiftUI

struct TaskScheduleEditor: View {
    @Binding var dueDate: Date?
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    static func isValid(startDate: Date?, endDate: Date?) -> Bool {
        guard let startDate, let endDate else { return true }
        return startDate <= endDate
    }

    private var isValid: Bool {
        Self.isValid(startDate: startDate, endDate: endDate)
    }

    var body: some View {
        Section("Schedule") {
            optionalDateRow(
                title: "Due Date",
                date: $dueDate,
                defaultValue: { Date() }
            )
            optionalDateRow(
                title: "Start Date",
                date: $startDate,
                defaultValue: { endDate ?? Date() }
            )
            optionalDateRow(
                title: "End Date",
                date: $endDate,
                defaultValue: { startDate ?? Date() }
            )

            if !isValid {
                Label("Start date must not be after end date.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid date range. Start date must not be after end date.")
            }
        }
    }

    @ViewBuilder
    private func optionalDateRow(
        title: String,
        date: Binding<Date?>,
        defaultValue: @escaping () -> Date
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { enabled in
                    date.wrappedValue = enabled ? (date.wrappedValue ?? defaultValue()) : nil
                }
            )
        )

        if date.wrappedValue != nil {
            DatePicker(
                title,
                selection: Binding(
                    get: { date.wrappedValue ?? defaultValue() },
                    set: { date.wrappedValue = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }
}
