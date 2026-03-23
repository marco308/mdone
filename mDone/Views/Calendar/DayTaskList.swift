import SwiftUI

struct DayTaskList: View {
    let date: Date
    let tasks: [VTask]
    var calendarEvents: [CalendarEvent] = []

    private var isEmpty: Bool {
        tasks.isEmpty && calendarEvents.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No tasks or events for this day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    if !tasks.isEmpty {
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

                    if !calendarEvents.isEmpty {
                        Section {
                            ForEach(calendarEvents) { event in
                                CalendarEventRow(event: event)
                            }
                        } header: {
                            Label("Calendar", systemImage: "calendar")
                                .font(.caption)
                                .textCase(.uppercase)
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
    }
}
