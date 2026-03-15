import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .inbox

    enum Tab: Hashable {
        case inbox, projects, calendar, settings
    }

    var body: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            SwiftUI.Tab("Inbox", systemImage: "tray.fill", value: Tab.inbox) {
                NavigationStack {
                    TaskListScreen()
                }
            }

            SwiftUI.Tab("Projects", systemImage: "folder.fill", value: Tab.projects) {
                NavigationStack {
                    ProjectListScreen()
                }
            }

            SwiftUI.Tab("Calendar", systemImage: "calendar", value: Tab.calendar) {
                NavigationStack {
                    CalendarScreen()
                }
            }

            SwiftUI.Tab("Settings", systemImage: "gearshape.fill", value: Tab.settings) {
                NavigationStack {
                    SettingsScreen()
                }
            }
        }
        .tint(Color.accentColor)
        .task {
            await appState.refreshAll()
        }
        #else
        Text("macOS")
        #endif
    }
}
