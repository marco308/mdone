import SwiftUI

struct CalendarGrid: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let tasksForMonth: [Date: [VTask]]
    var eventsForMonth: [Date: [CalendarEvent]] = [:]

    private let calendar = Calendar.current
    private let weekdays = Calendar.current.shortWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            // Month header
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Next month")
            }
            .padding(.horizontal, 4)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date {
                        let dayKey = calendar.startOfDay(for: date)
                        DayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            tasks: tasksForMonth[dayKey] ?? [],
                            events: eventsForMonth[dayKey] ?? []
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = date
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50 {
                        changeMonth(by: 1)
                    } else if value.translation.width > 50 {
                        changeMonth(by: -1)
                    }
                }
        )
    }

    private func changeMonth(by value: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
            }
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: offset)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(date)
            }
        }

        return days
    }
}

struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let tasks: [VTask]
    var events: [CalendarEvent] = []

    private var hasEvents: Bool {
        !events.isEmpty
    }

    private var totalDots: Int {
        min(tasks.count, 3) + (hasEvents ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                .frame(width: 32, height: 32)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }

            // Task and event dots
            HStack(spacing: 2) {
                ForEach(0 ..< min(tasks.count, 3), id: \.self) { index in
                    Circle()
                        .fill(dotColor(for: tasks[index]))
                        .frame(width: 5, height: 5)
                }

                if hasEvents {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayCellAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var dayCellAccessibilityLabel: String {
        var label = date.formatted(date: .complete, time: .omitted)
        if isToday {
            label += ", today"
        }
        if !tasks.isEmpty {
            label += ", \(tasks.count) \(tasks.count == 1 ? "task" : "tasks")"
        }
        return label
    }

    private func dotColor(for task: VTask) -> Color {
        switch task.priorityLevel {
        case .critical, .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .none: .gray
        }
    }
}
