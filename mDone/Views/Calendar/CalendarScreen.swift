import SwiftUI

struct CalendarScreen: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDate: Date = .init()
    @State private var displayedMonth: Date = .init()
    @State private var dayCalendarEvents: [CalendarEvent] = []
    @State private var monthCalendarEvents: [Date: [CalendarEvent]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Calendar access banner
            if !appState.calendarAccessGranted {
                calendarAccessBanner
            }

            CalendarGrid(
                displayedMonth: $displayedMonth,
                selectedDate: $selectedDate,
                tasksForMonth: appState.datesWithTasks(in: displayedMonth),
                eventsForMonth: monthCalendarEvents
            )
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            DayTaskList(
                date: selectedDate,
                tasks: appState.tasksForDate(selectedDate),
                calendarEvents: dayCalendarEvents
            )
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        selectedDate = Date()
                        displayedMonth = Date()
                    }
                } label: {
                    Text("Today")
                        .font(.subheadline)
                }
                .accessibilityLabel("Go to today")
            }
        }
        .task {
            await appState.requestCalendarAccess()
        }
        // Folding the filter token into each id means the day refetches only
        // when the day or the calendar selection changes (likewise the month),
        // and every task fires exactly once on first appear — no duplicate
        // EventKit reads.
        .task(id: CalendarFetchKey(date: selectedDate, token: appState.calendarFilterToken)) {
            dayCalendarEvents = await appState.calendarEventsForDate(selectedDate)
        }
        .task(id: CalendarFetchKey(date: displayedMonth, token: appState.calendarFilterToken)) {
            monthCalendarEvents = await appState.calendarEventsForMonth(displayedMonth)
        }
    }

    private var calendarAccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)

            Text("Enable calendar access to see events")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #elseif os(macOS)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

/// Composite `.task(id:)` key so an event fetch re-runs when either the
/// date (day or month) or the visible-calendar selection changes.
private struct CalendarFetchKey: Hashable {
    let date: Date
    let token: UUID
}
