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
        // On iPad this turns the tab bar into a proper sidebar (the user can
        // collapse it back to a tab bar); on iPhone it stays a plain tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .background { keyboardShortcuts }
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
        // Changes the sync queue gave up on must not disappear quietly: the
        // user thinks they made that edit (issue #146).
        .alert(
            "Some changes could not be synced",
            isPresented: Binding(
                get: { !appState.failedSyncMessages.isEmpty },
                set: {
                    if !$0 {
                        appState.failedSyncMessages = []
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { appState.failedSyncMessages = [] }
        } message: {
            Text(appState.failedSyncMessages.joined(separator: "\n\n"))
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
    /// Hardware-keyboard shortcuts (iPad with a keyboard, mainly). The buttons
    /// are invisible: they exist only to carry the key equivalents, and their
    /// titles are what the hold-Command discoverability overlay displays.
    private var keyboardShortcuts: some View {
        Group {
            Button("New Task") {
                // Same pipeline as the widget and the Shortcuts action: the
                // onChange above switches to Inbox, QuickAddBar grabs focus.
                appState.quickAddTrigger = UUID()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Refresh") {
                Task { await appState.refreshAll() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Inbox") { selectedTab = .inbox }
                .keyboardShortcut("1", modifiers: .command)
            Button("Projects") { selectedTab = .projects }
                .keyboardShortcut("2", modifiers: .command)
            Button("Calendar") { selectedTab = .calendar }
                .keyboardShortcut("3", modifiers: .command)
            Button("Settings") { selectedTab = .settings }
                .keyboardShortcut("4", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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
