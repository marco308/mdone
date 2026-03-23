import SwiftUI

struct MacTaskListView: View {
    @Environment(AppState.self) private var appState
    let section: MacContentView.SidebarSection?
    @Binding var selectedTask: VTask?
    @State private var sortOrder: SortOrder = .dueDate
    @State private var showAdvancedFilter = false

    enum SortOrder: String, CaseIterable {
        case dueDate = "Due Date"
        case priority = "Priority"
        case title = "Title"
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
                List(selection: $selectedTask) {
                    if !appState.overdueTasks.isEmpty {
                        SmartListSection(title: "Overdue", tasks: appState.overdueTasks, accentColor: .red)
                    }
                    if !appState.todayTasks.isEmpty {
                        SmartListSection(title: "Today", tasks: appState.todayTasks, accentColor: Color.accentColor)
                    }
                    if !appState.tomorrowTasks.isEmpty {
                        SmartListSection(title: "Tomorrow", tasks: appState.tomorrowTasks, accentColor: .orange)
                    }
                    if !appState.thisWeekTasks.isEmpty {
                        SmartListSection(title: "This Week", tasks: appState.thisWeekTasks, accentColor: .blue)
                    }
                    if !appState.upcomingTasks.isEmpty {
                        SmartListSection(title: "Upcoming", tasks: appState.upcomingTasks, accentColor: .purple)
                    }
                    if !appState.noDateTasks.isEmpty {
                        SmartListSection(title: "No Date", tasks: appState.noDateTasks, accentColor: .secondary)
                    }
                }
                .listStyle(.inset)
            } else {
                List(tasks, selection: $selectedTask) { task in
                    TaskRow(task: task)
                        .tag(task)
                        .draggable(String(task.id)) {
                            Text(task.title)
                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
                .listStyle(.inset)
                .dropDestination(for: String.self) { droppedIds, location in
                    guard let draggedIdStr = droppedIds.first,
                          let draggedId = Int64(draggedIdStr) else { return false }
                    handleDrop(taskId: draggedId, in: tasks, at: location)
                    return true
                }
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
                    Image(systemName: appState.advancedFilterString != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Advanced Filter")
                .popover(isPresented: $showAdvancedFilter) {
                    TaskFilterSheet { filterString in
                        Task { await appState.applyAdvancedFilter(filterString) }
                    }
                    .frame(width: 350, height: 450)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort tasks")
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
        guard let section else { return "Tasks" }
        switch section {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        case .upcoming: return "Upcoming"
        case .overdue: return "Overdue"
        case .noDate: return "No Date"
        case let .project(project): return project.title
        case .notifications: return "Notifications"
        case .calendar: return "Calendar"
        case .settings: return "Settings"
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
        case .notifications, .calendar, .settings: return []
        }
    }

    private func handleDrop(taskId: Int64, in tasks: [VTask], at location: CGPoint) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }

        // Estimate the target index based on list position
        // Use a simple approach: calculate position as midpoint between neighbors
        let estimatedRowHeight: CGFloat = 60
        let targetIndex = min(max(Int(location.y / estimatedRowHeight), 0), tasks.count - 1)

        let newPosition: Double
        if tasks.count <= 1 {
            newPosition = 0
        } else if targetIndex == 0 {
            newPosition = (tasks[0].position ?? 0) - 1
        } else if targetIndex >= tasks.count - 1 {
            newPosition = (tasks[tasks.count - 1].position ?? Double(tasks.count)) + 1
        } else {
            let before = tasks[targetIndex].position ?? Double(targetIndex)
            let after = tasks[targetIndex + 1].position ?? Double(targetIndex + 1)
            newPosition = (before + after) / 2
        }

        // Default view ID; ideally this would come from the project's default view
        let viewId: Int64 = 0

        Task {
            await appState.moveTask(task, toPosition: newPosition, viewId: viewId)
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

        switch sortOrder {
        case .dueDate:
            tasks.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .priority:
            tasks.sort { $0.priority > $1.priority }
        case .title:
            tasks.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }

        return tasks
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
        case .calendar, .settings: return "tray"
        }
    }

    private var emptyStateTitle: String {
        guard let section else { return "No Tasks" }
        switch section {
        case .today: return "All Clear Today"
        case .tomorrow: return "Nothing Tomorrow"
        case .thisWeek: return "Nothing This Week"
        case .upcoming: return "Nothing Upcoming"
        case .overdue: return "No Overdue Tasks"
        case .noDate: return "No Undated Tasks"
        case .inbox: return "No Active Tasks"
        case .project: return "No Tasks in Project"
        case .notifications: return "No Notifications"
        case .calendar, .settings: return "No Tasks"
        }
    }

    private var emptyStateSubtitle: String {
        guard let section else { return "" }
        switch section {
        case .today: return "You have no tasks due today."
        case .tomorrow: return "No tasks due tomorrow."
        case .thisWeek: return "No tasks due this week."
        case .upcoming: return "No tasks coming up."
        case .overdue: return "Great job staying on top of things!"
        case .noDate: return "All your tasks have due dates."
        case .inbox: return "Create a task to get started."
        case .project: return "Add a task to this project."
        case .notifications: return "You're all caught up!"
        case .calendar, .settings: return ""
        }
    }
}
