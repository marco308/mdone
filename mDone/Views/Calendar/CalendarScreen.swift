import SwiftUI

struct CalendarScreen: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            CalendarGrid(
                displayedMonth: $displayedMonth,
                selectedDate: $selectedDate,
                tasksForMonth: appState.datesWithTasks(in: displayedMonth)
            )
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            DayTaskList(
                date: selectedDate,
                tasks: appState.tasksForDate(selectedDate)
            )
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        selectedDate = Date()
                        displayedMonth = Date()
                    }
                } label: {
                    Text("Today")
                        .font(.subheadline)
                }
            }
        }
    }
}
