import SwiftUI

struct MacTaskListView: View {
    @Environment(AppState.self) private var appState
    let section: MacContentView.SidebarSection?
    @Binding var selectedTask: VTask?
    @State private var showAdvancedFilter = false
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
    /// with the project's order.
    private var manualOrderActive: Bool {
        guard case .project = section else { return false }
        return sortPreference.order == .manual
            && appState.activeFilter == nil
            && appState.searchQuery.isEmpty
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
    }

    @ViewBuilder
    private var taskListContent: some View {
        @Bindable var appState = appState
        let tasks = filteredAndSortedTasks
        VStack(spacing: 0) {
            FilterBar(activeFilter: $appState.activeFilter)

            if tasks.isEmpty, appState.searchQuery.isEmpty {
                EmptyStateView(
                    icon: emptyStateIcon,
                    title: emptyStateTitle,
                    subtitle: emptyStateSubtitle
                )
                .frame(maxHeight: .infinity)
            } else if tasks.isEmpty {
                ContentUnavailableView.search(text: appState.searchQuery)
                    .frame(maxHeight: .infinity)
            } else if section == .inbox {
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
        .onSubmit(of: .search) {
            Task { await appState.searchTasks(query: appState.searchQuery) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdvancedFilter.toggle()
                } label: {
                    Image(systemName: appState
                        .advancedFilterString != nil ? "line.3.horizontal.decrease.circle.fill" :
                        "line.3.horizontal.decrease.circle")
                }
                .help("Advanced Filter")
                .accessibilityLabel(appState.advancedFilterString != nil ? "Advanced filter active" : "Advanced filter")
                .popover(isPresented: $showAdvancedFilter) {
                    TaskFilterSheet { filterString in
                        Task { await appState.applyAdvancedFilter(filterString) }
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
        var tasks = tasksForSection

        if let activeFilter = appState.activeFilter {
            tasks = activeFilter.apply(to: tasks)
        }

        if !appState.searchQuery.isEmpty {
            let query = appState.searchQuery.lowercased()
            tasks = tasks.filter { $0.title.lowercased().contains(query) }
        }

        return sortPreference.apply(to: tasks)
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
