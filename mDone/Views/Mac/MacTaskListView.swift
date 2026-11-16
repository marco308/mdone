import SwiftUI

struct MacTaskListView: View {
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase
    let section: MacContentView.SidebarSection?
    @Binding var selectedTask: VTask?
    @State private var showAdvancedFilter = false
    #if os(macOS)
    /// mDone is the frontmost app. Behind other apps the list polls far less.
    @State private var appIsFrontmost = NSApplication.shared.isActive
    /// Some of mDone's window is on screen: not minimised, hidden or covered.
    @State private var appIsVisible = NSApplication.shared.occlusionState.contains(.visible)
    #endif
    @AppStorage("calmMode") private var calmMode = false

    private var sortScope: TaskSortScope {
        if case let .project(project) = section {
            return .project(project.id)
        }
        return .inbox
    }

    private var sortPreference: TaskSortPreference {
        appState.sortPreference(for: sortScope)
    }

    /// Rows can be dragged only while a project list shows the server's
    /// order, with nothing filtered out: under another sort the drop would
    /// be sorted straight back, and a filtered list's indices don't line up
    /// with the project's order. A virtual project (saved filter, negative
    /// id) is excluded: `moveTask` positions by the task's real home
    /// project, so dragging here would write the position into that
    /// project's list view instead of the filter's (#209).
    private var manualOrderActive: Bool {
        guard case let .project(project) = section else { return false }
        return project.id >= 0
            && sortPreference.order == .manual
            && !appState.isFiltering
    }

    /// Whether the list keeps itself up to date with changes made on another
    /// device (#241), the way the iOS list does. A Mac window often stays on
    /// screen beside other apps, so it keeps polling there, slowly; once no
    /// part of it can be seen, polling stops. The advanced filter popover
    /// pauses it, as on iOS. Changing this restarts or stops the polling task.
    private var liveRefreshActive: Bool {
        sectionShowsTasks && scenePhase != .background && appState.isAuthenticated
            && networkMonitor.isConnected && !showAdvancedFilter && appOnScreen
    }

    private var appOnScreen: Bool {
        #if os(macOS)
        appIsVisible
        #else
        true
        #endif
    }

    private var appInFront: Bool {
        #if os(macOS)
        appIsFrontmost
        #else
        true
        #endif
    }

    private var pollPace: LivePollPace {
        .current(inFront: appInFront, constrained: LivePollPace.isConstrained(network: networkMonitor))
    }

    private var sectionShowsTasks: Bool {
        switch section {
        case .inbox, .today, .tomorrow, .thisWeek, .upcoming, .overdue, .noDate, .project:
            return true
        case .archived, .notifications, .calendar, .settings, .none:
            return false
        }
    }

    /// Coming to the front restarts the loop, so a long wait picked while
    /// behind other apps does not carry over.
    private struct LiveRefreshKey: Equatable {
        let projectId: Int64?
        let isActive: Bool
        let inFront: Bool
    }

    /// One quiet read of the visible list. `nil` reads the tasks behind the
    /// Inbox and the date sections; a project also reads its list view.
    /// `force` skips the change check and reads the full list.
    private func refreshVisibleList(force: Bool = false) async -> LiveRefreshOutcome {
        await appState.refreshVisibleList(project: selectedProject, force: force) { liveRefreshActive }
    }

    var body: some View {
        Group {
            switch section {
            case .calendar:
                CalendarScreen()
            case .settings:
                SettingsScreen()
            case .notifications:
                NotificationListView()
            case .none:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose a section from the sidebar")
                )
            default:
                taskListContent
            }
        }
        .navigationTitle(sectionTitle)
        // A saved filter's tasks come only from its list view, so it stays
        // empty until that view is read (#278). Reading it also caches the
        // project, which makes `refreshAll` keep it current from then on.
        .task(id: selectedProject?.id) {
            if let selectedProject {
                await appState.fetchProjectTasks(project: selectedProject)
            }
        }
        .task(id: LiveRefreshKey(projectId: selectedProject?.id, isActive: liveRefreshActive, inFront: appInFront)) {
            guard liveRefreshActive else { return }
            await LiveListRefresh.poll(pace: { pollPace }, refresh: {
                await refreshVisibleList()
            })
        }
        #if os(macOS)
        // On the Mac the scene stays active while another app is in front,
        // so coming back to mDone never changes `scenePhase` and the app-wide
        // refresh on activation does not run. Catch up straight away, with a
        // full read: the change check misses reorders made elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsFrontmost = true
            Task { await refreshVisibleList(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsFrontmost = false
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeOcclusionStateNotification
        )) { _ in
            appIsVisible = NSApplication.shared.occlusionState.contains(.visible)
        }
        #endif
    }

    private var selectedProject: Project? {
        if case let .project(project) = section {
            return project
        }
        return nil
    }

    @ViewBuilder
    private var taskListContent: some View {
        @Bindable var appState = appState
        let tasks = filteredAndSortedTasks
        VStack(spacing: 0) {
            FilterBar(activeFilter: $appState.activeFilter)

            if tasks.isEmpty, !appState.isFiltering {
                EmptyStateView(
                    icon: emptyStateIcon,
                    title: emptyStateTitle,
                    subtitle: emptyStateSubtitle
                )
                .frame(maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView.search(text: appState.searchQuery)
                    .frame(maxHeight: .infinity)
            } else if section == .inbox, !appState.isFiltering {
                // The sections read AppState directly, so while a filter or
                // search is on the Inbox falls through to the flat list of
                // `tasks` below; otherwise filtering would change nothing.
                let currentTasks = appState.currentTasks
                let currentIds = Set(currentTasks.map(\.id))
                List(selection: $selectedTask) {
                    if !currentTasks.isEmpty {
                        SmartListSection(
                            title: String(localized: "Current"),
                            tasks: currentTasks,
                            accentColor: Color.accentColor,
                            showsProgress: true
                        )
                    }
                    if calmMode {
                        let todayAndOverdue = excludingCurrent(appState.calmModeTodayTasks, currentIds: currentIds)
                        if !todayAndOverdue.isEmpty {
                            SmartListSection(
                                title: String(localized: "Today"),
                                tasks: todayAndOverdue,
                                accentColor: Color.accentColor
                            )
                        }
                    } else {
                        let overdue = excludingCurrent(appState.overdueTasks, currentIds: currentIds)
                        if !overdue.isEmpty {
                            SmartListSection(title: String(localized: "Overdue"), tasks: overdue, accentColor: .red)
                        }
                        let today = excludingCurrent(appState.todayTasks, currentIds: currentIds)
                        if !today.isEmpty {
                            SmartListSection(
                                title: String(localized: "Today"),
                                tasks: today,
                                accentColor: Color.accentColor
                            )
                        }
                    }
                    let tomorrow = excludingCurrent(appState.tomorrowTasks, currentIds: currentIds)
                    if !tomorrow.isEmpty {
                        SmartListSection(title: String(localized: "Tomorrow"), tasks: tomorrow, accentColor: .orange)
                    }
                    let thisWeek = excludingCurrent(appState.thisWeekTasks, currentIds: currentIds)
                    if !thisWeek.isEmpty {
                        SmartListSection(title: String(localized: "This Week"), tasks: thisWeek, accentColor: .blue)
                    }
                    let upcoming = excludingCurrent(appState.upcomingTasks, currentIds: currentIds)
                    if !upcoming.isEmpty {
                        SmartListSection(title: String(localized: "Upcoming"), tasks: upcoming, accentColor: .purple)
                    }
                    let noDate = excludingCurrent(appState.noDateTasks, currentIds: currentIds)
                    if !noDate.isEmpty {
                        SmartListSection(title: String(localized: "No Date"), tasks: noDate, accentColor: .secondary)
                    }
                }
                .listStyle(.inset)
            } else {
                let rows = TaskNesting.rows(for: tasks)
                let hasNesting = rows.contains { $0.depth > 0 }
                List(selection: $selectedTask) {
                    // Reorder is flat-only and manual-sort-only; when flat,
                    // `rows` preserves `tasks`' order so the move indices
                    // line up.
                    ForEach(rows) { row in
                        TaskRow(task: row.task, indentLevel: row.depth)
                            .tag(row.task)
                            .moveDisabled(hasNesting || !manualOrderActive)
                    }
                    .onMove { source, destination in
                        handleMove(tasks: tasks, from: source, to: destination)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $appState.searchQuery, prompt: "Filter tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdvancedFilter.toggle()
                } label: {
                    Image(systemName: appState.advancedFilter.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .help("Advanced Filter")
                .accessibilityLabel(appState.advancedFilter.isActive ? "Advanced filter active" : "Advanced filter")
                .popover(isPresented: $showAdvancedFilter) {
                    TaskFilterSheet(filter: appState.advancedFilter) { filter in
                        appState.advancedFilter = filter
                    }
                    .frame(width: 350, height: 450)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                TaskSortMenu(scope: sortScope)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var sectionTitle: String {
        guard let section else { return String(localized: "Tasks") }
        switch section {
        case .inbox: return String(localized: "Inbox")
        case .today: return String(localized: "Today")
        case .tomorrow: return String(localized: "Tomorrow")
        case .thisWeek: return String(localized: "This Week")
        case .upcoming: return String(localized: "Upcoming")
        case .overdue: return String(localized: "Overdue")
        case .noDate: return String(localized: "No Date")
        case let .project(project): return project.title
        case .archived: return String(localized: "Archived")
        case .notifications: return String(localized: "Notifications")
        case .calendar: return String(localized: "Calendar")
        case .settings: return String(localized: "Settings")
        }
    }

    private var tasksForSection: [VTask] {
        guard let section else { return [] }
        switch section {
        case .inbox: return appState.activeTasks
        case .today: return appState.todayTasks
        case .tomorrow: return appState.tomorrowTasks
        case .thisWeek: return appState.thisWeekTasks
        case .upcoming: return appState.upcomingTasks
        case .overdue: return appState.overdueTasks
        case .noDate: return appState.noDateTasks
        case let .project(project): return appState.tasksForProject(project.id)
        case .archived, .notifications, .calendar, .settings: return []
        }
    }

    /// Removes tasks already shown in the Current section so they don't appear
    /// twice in the date-based sections below it.
    private func excludingCurrent(_ tasks: [VTask], currentIds: Set<Int64>) -> [VTask] {
        currentIds.isEmpty ? tasks : tasks.filter { !currentIds.contains($0.id) }
    }

    private func handleMove(tasks: [VTask], from source: IndexSet, to destination: Int) {
        guard let move = TaskPositioning.move(tasks, fromOffsets: source, toOffset: destination) else { return }
        Task {
            await appState.moveTask(move.task, toPosition: move.position, newOrder: move.reordered)
        }
    }

    private var filteredAndSortedTasks: [VTask] {
        // The Inbox normally lists open tasks only. Once a filter is on it
        // searches every task, as on iOS, so "Completed" or Status: Done can
        // actually find something.
        let base = section == .inbox && appState.isFiltering ? appState.tasks : tasksForSection
        return sortPreference.apply(to: appState.applyingFilters(to: base))
    }

    private var emptyStateIcon: String {
        guard let section else { return "tray" }
        switch section {
        case .today: return "sun.max"
        case .tomorrow: return "sunrise"
        case .thisWeek: return "calendar.badge.clock"
        case .upcoming: return "calendar"
        case .overdue: return "checkmark.circle"
        case .noDate: return "tray"
        case .inbox: return "tray"
        case .project: return "folder"
        case .notifications: return "bell"
        case .archived, .calendar, .settings: return "tray"
        }
    }

    private var emptyStateTitle: String {
        guard let section else { return String(localized: "No Tasks") }
        switch section {
        case .today: return String(localized: "All Clear Today")
        case .tomorrow: return String(localized: "Nothing Tomorrow")
        case .thisWeek: return String(localized: "Nothing This Week")
        case .upcoming: return String(localized: "Nothing Upcoming")
        case .overdue: return String(localized: "No Overdue Tasks")
        case .noDate: return String(localized: "No Undated Tasks")
        case .inbox: return String(localized: "No Active Tasks")
        case .project: return String(localized: "No Tasks in Project")
        case .notifications: return String(localized: "No Notifications")
        case .archived, .calendar, .settings: return String(localized: "No Tasks")
        }
    }

    private var emptyStateSubtitle: String {
        guard let section else { return "" }
        switch section {
        case .today: return String(localized: "You have no tasks due today.")
        case .tomorrow: return String(localized: "No tasks due tomorrow.")
        case .thisWeek: return String(localized: "No tasks due this week.")
        case .upcoming: return String(localized: "No tasks coming up.")
        case .overdue: return String(localized: "Great job staying on top of things!")
        case .noDate: return String(localized: "All your tasks have due dates.")
        case .inbox: return String(localized: "Create a task to get started.")
        case .project: return String(localized: "Add a task to this project.")
        case .notifications: return String(localized: "You're all caught up!")
        case .archived, .calendar, .settings: return ""
        }
    }
}
