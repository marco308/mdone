import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    @State private var selectedTab: Tab = .inbox
    @State private var showNotifications = false
    #if os(iOS)
    @State private var showUndoCompletionPrompt = false
    #endif

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
        .onChange(of: appState.quickAddTrigger) { _, newValue in
            if newValue != nil {
                selectedTab = .inbox
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationListView()
        }
        .fullScreenCover(isPresented: Bindable(focusManager).showFocusView) {
            FocusSessionView()
        }
        .errorBanner(Bindable(appState).activeError) {
            Task { await appState.refreshAll() }
        }
        .onShake {
            if appState.canUndoLastCompletion {
                showUndoCompletionPrompt = true
            }
        }
        .confirmationDialog(
            undoPromptTitle,
            isPresented: $showUndoCompletionPrompt,
            titleVisibility: .visible
        ) {
            Button("Undo Completion") {
                Task { await appState.undoLastCompletion() }
            }
            Button("Cancel", role: .cancel) {}
        }
        #else
        Text("macOS")
        #endif
    }

    #if os(iOS)
    private var undoPromptTitle: String {
        if let title = appState.undoableCompletionTitle {
            return "Undo completing \u{201C}\(title)\u{201D}?"
        }
        return "Undo completion?"
    }
    #endif

    private var notificationBellButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.body)

                if appState.unreadNotificationCount > 0 {
                    Text("\(appState.unreadNotificationCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 8, y: -8)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(appState
            .unreadNotificationCount > 0 ? "Notifications, \(appState.unreadNotificationCount) unread" :
            "Notifications")
    }
}
