import SwiftUI

/// Lets the user choose which device calendars contribute events to mDone.
/// Selections are persisted via `HiddenCalendarStore`; toggling one refreshes
/// the in-memory event list immediately.
struct CalendarSelectionView: View {
    @Environment(AppState.self) private var appState

    private let store = HiddenCalendarStore()

    @State private var calendars: [CalendarInfo] = []
    @State private var hidden: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if calendars.isEmpty {
                ContentUnavailableView(
                    "No Calendars",
                    systemImage: "calendar",
                    description: Text(
                        "mDone has no calendars to show. Grant calendar access in the Calendar tab first."
                    )
                )
            } else {
                Section {
                    ForEach(calendars) { calendar in
                        Toggle(isOn: binding(for: calendar)) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(cgColor: calendar.color ?? Self.fallbackColor))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(calendar.title)
                            }
                        }
                    }
                } footer: {
                    Text("Only events from the calendars you turn on appear in mDone's Calendar and Today views.")
                }
            }
        }
        .navigationTitle("Calendars")
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
            .toolbar {
                if !calendars.isEmpty {
                    Button(allShown ? "Hide All" : "Show All") {
                        toggleAll()
                    }
                }
            }
            .task {
                calendars = await appState.availableCalendars()
                // Drop hidden entries for calendars that no longer exist, then
                // read the persisted set back so the toggles always reflect
                // exactly what the store holds.
                store.prune(toExisting: Set(calendars.map(\.id)))
                hidden = store.hiddenIdentifiers
                isLoading = false
            }
    }

    private static let fallbackColor = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)

    private var allShown: Bool {
        hidden.isEmpty
    }

    private func binding(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(calendar.id) },
            set: { shown in
                if shown {
                    hidden.remove(calendar.id)
                } else {
                    hidden.insert(calendar.id)
                }
                store.setHidden(!shown, for: calendar.id)
                Task { await appState.calendarSelectionDidChange() }
            }
        )
    }

    private func toggleAll() {
        if allShown {
            hidden = Set(calendars.map(\.id))
        } else {
            hidden = []
        }
        store.replace(with: hidden)
        Task { await appState.calendarSelectionDidChange() }
    }
}
