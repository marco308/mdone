import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    @State private var selectedTab: Tab = .inbox
    @State private var showNotifications = false

    enum Tab: Hashable {
        case inbox, projects, calendar, settings
    }

    var body: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            SwiftUI.Tab("Inbox", systemImage: "tray.fill", value: Tab.inbox) {
                NavigationStack {
                    TaskListScreen()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                notificationBellButton
                            }
                        }
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
            await appState.fetchNotifications()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationListView()
        }
        .fullScreenCover(isPresented: Bindable(focusManager).showFocusView) {
            FocusSessionView()
        }
        #else
        Text("macOS")
        #endif
    }

    private var notificationBellButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.body)

                if appState.unreadNotificationCount > 0 {
                    Text("\(appState.unreadNotificationCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}
