import SwiftUI

struct DayTaskList: View {
    let date: Date
    let tasks: [VTask]

    var body: some View {
        Group {
            if tasks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No tasks for this day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    Section {
                        ForEach(tasks) { task in
                            TaskRow(task: task)
                        }
                    } header: {
                        Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.caption)
                            .textCase(.uppercase)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}
