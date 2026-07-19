import SwiftUI

struct TaskListScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    var projectFilter: Project?
    /// When true, hides the quick-add bar — used for archived (read-only) projects.
    var readOnly: Bool = false
    @State private var showAdvancedFilter = false
    @State private var sortOrder: SortOrder = .dueDate
    @State private var sortAscending: Bool = true
    @AppStorage("calmMode") private var calmMode = false
    #if os(iOS)
    @State private var showBoard = false
    #endif

    /// A board (Kanban) view is offered only for real, editable projects that
    /// have a kanban view configured on the server.
    private var boardAvailable: Bool {
        !readOnly && projectFilter?.kanbanViewId != nil
    }

    /// True while the board is displayed instead of the list. The filter and
    /// sort controls only affect the list, so they're hidden in board mode.
    private var boardActive: Bool {
        #if os(iOS)
        return showBoard && projectFilter != nil
        #else
        return false
        #endif
    }

    enum SortOrder: String, CaseIterable {
        case dueDate = "Due Date"
        case priority = "Priority"
        case title = "Title"
    }

    var body: some View {
        @Bindable var bindableAppState = appState
        content
            .task(id: projectFilter?.id) {
                if let projectFilter {
                    await appState.fetchProjectTasks(project: projectFilter)
                }
            }
            .task {
                await appState.requestCalendarAccess()
            }
            .searchable(text: $bindableAppState.searchQuery, prompt: "Search tasks")
            .onSubmit(of: .search) {
                Task { await appState.searchTasks(query: appState.searchQuery) }
            }
            .navigationTitle(projectFilter?.title ?? "Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbarContent }
                .sheet(isPresented: $showAdvancedFilter) {
                    TaskFilterSheet { filterString in
                        Task { await appState.applyAdvancedFilter(filterString) }
                    }
                }
                .overlay {
                    if appState.isLoading, appState.tasks.isEmpty {
                        LoadingOverlay()
                    }
                }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if showBoard, let projectFilter {
            ProjectBoardView(project: projectFilter)
        } else {
            listBody
        }
        #else
        listBody
        #endif
    }

    private var listBody: some View {
        @Bindable var bindableAppState = appState
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                FilterBar(activeFilter: $bindableAppState.activeFilter)

                List {
                    #if os(iOS)
                    if let session = focusManager.currentSession {
                        FocusBanner(session: session) {
                            focusManager.showFocusView = true
                        }
                    }
                    #endif

                    if !networkMonitor.isConnected {
                        offlineBanner
                    }

                    if isFiltering {
                        filteredTaskSection
                    } else if let projectFilter {
                        let projectTasks = sorted(appState.tasksForProject(projectFilter.id))
                        if projectTasks.isEmpty {
                            Section {
                                EmptyStateView(
                                    icon: "checkmark.circle",
                                    title: "No tasks",
                                    subtitle: "Add a task to get started"
                                )
                            }
                        } else {
                            Section {
                                if readOnly {
                                    ForEach(projectTasks) { task in
                                        TaskRow(task: task, readOnly: true)
                                    }
                                } else {
                                    ForEach(projectTasks) { task in
                                        TaskRow(task: task)
                                    }
                                    .onMove { source, destination in
                                        handleMove(tasks: projectTasks, from: source, to: destination)
                                    }
                                }
                            }
                        }
                    } else {
                        smartListSections
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .contentMargins(.bottom, 72, for: .scrollContent)
                .refreshable {
                    await appState.refreshAll()
                    if let projectFilter {
                        await appState.fetchProjectTasks(project: projectFilter)
                    }
                }
            }

            if !readOnly {
                QuickAddBar(
                    projectId: projectFilter?.id ?? defaultProjectId,
                    defaultDueDate: projectFilter == nil ? DefaultDueTimePreference.apply(to: Date()) : nil
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        if boardAvailable {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBoard.toggle()
                } label: {
                    Image(systemName: showBoard ? "list.bullet" : "rectangle.split.3x1")
                }
                .accessibilityLabel(showBoard ? "Show list" : "Show board")
            }
        }
        #endif

        if !boardActive {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdvancedFilter = true
                } label: {
                    Image(systemName: appState
                        .advancedFilterString != nil ? "line.3.horizontal.decrease.circle.fill" :
                        "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(appState
                    .advancedFilterString != nil ? "Advanced filter active" : "Advanced filter")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            if sortOrder == order {
                                sortAscending.toggle()
                            } else {
                                sortOrder = order
                                sortAscending = true
                            }
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort by \(sortOrder.rawValue), \(sortAscending ? "ascending" : "descending")")
            }
        }
    }

    private var isFiltering: Bool {
        !appState.searchQuery.isEmpty || appState.activeFilter != nil
    }

    @ViewBuilder
    private var filteredTaskSection: some View {
        let allFiltered = appState.filteredTasks
        let filtered = if let projectFilter {
            allFiltered.filter { $0.projectId == projectFilter.id }
        } else {
            allFiltered
        }
        let tasks = sorted(filtered)
        if tasks.isEmpty {
            Section {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a different search or filter"
                )
            }
        } else {
            Section("Results (\(tasks.count))") {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                }
            }
        }
    }

    private var defaultProjectId: Int64 {
        appState.projects.first?.id ?? 1
    }

    @ViewBuilder
    private var smartListSections: some View {
        let currentTasks = appState.currentTasks
        let currentIds = Set(currentTasks.map(\.id))

        if !currentTasks.isEmpty {
            SmartListSection(
                title: "Current",
                tasks: currentTasks,
                accentColor: Color.accentColor,
                showsProgress: true
            )
        }

        if calmMode {
            // Calm Mode: overdue tasks aren't singled out, they fold into Today.
            let todayAndOverdue = excludingCurrent(appState.calmModeTodayTasks, currentIds: currentIds)
            if !todayAndOverdue.isEmpty {
                SmartListSection(
                    title: "Today",
                    tasks: sorted(todayAndOverdue),
                    accentColor: Color.accentColor
                )
            }
        } else {
            let overdue = excludingCurrent(appState.overdueTasks, currentIds: currentIds)
            if !overdue.isEmpty {
                SmartListSection(
                    title: "Overdue",
                    tasks: sorted(overdue),
                    accentColor: .red
                )
            }

            let today = excludingCurrent(appState.todayTasks, currentIds: currentIds)
            if !today.isEmpty {
                SmartListSection(
                    title: "Today",
                    tasks: sorted(today),
                    accentColor: Color.accentColor
                )
            }
        }

        if appState.calendarAccessGranted, !appState.todayCalendarEvents.isEmpty {
            Section {
                ForEach(appState.todayCalendarEvents) { event in
                    CalendarEventRow(event: event)
                }
            } header: {
                HStack {
                    Image(systemName: "calendar")
                    Text("Today's Events")
                    Spacer()
                    Text("\(appState.todayCalendarEvents.count)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green, in: Capsule())
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
            }
        }

        let tomorrow = excludingCurrent(appState.tomorrowTasks, currentIds: currentIds)
        if !tomorrow.isEmpty {
            SmartListSection(
                title: "Tomorrow",
                tasks: sorted(tomorrow),
                accentColor: .orange
            )
        }

        let thisWeek = excludingCurrent(appState.thisWeekTasks, currentIds: currentIds)
        if !thisWeek.isEmpty {
            SmartListSection(
                title: "This Week",
                tasks: sorted(thisWeek),
                accentColor: .blue
            )
        }

        let upcoming = excludingCurrent(appState.upcomingTasks, currentIds: currentIds)
        if !upcoming.isEmpty {
            SmartListSection(
                title: "Upcoming",
                tasks: sorted(upcoming),
                accentColor: .purple
            )
        }

        let noDate = excludingCurrent(appState.noDateTasks, currentIds: currentIds)
        if !noDate.isEmpty {
            SmartListSection(
                title: "No Date",
                tasks: sorted(noDate),
                accentColor: .secondary
            )
        }

        if appState.activeTasks.isEmpty, !appState.isLoading {
            Section {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All done!",
                    subtitle: "No pending tasks"
                )
            }
        }
    }

    /// Removes tasks already shown in the Current section so they don't appear
    /// twice in the date-based sections below it.
    private func excludingCurrent(_ tasks: [VTask], currentIds: Set<Int64>) -> [VTask] {
        currentIds.isEmpty ? tasks : tasks.filter { !currentIds.contains($0.id) }
    }

    private func sorted(_ tasks: [VTask]) -> [VTask] {
        tasks.sorted { a, b in
            let result: Bool = switch sortOrder {
            case .dueDate:
                (a.effectiveDueDate ?? .distantFuture) < (b.effectiveDueDate ?? .distantFuture)
            case .priority:
                a.priority > b.priority
            case .title:
                a.title.localizedCompare(b.title) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    private func handleMove(tasks: [VTask], from source: IndexSet, to destination: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: source, toOffset: destination)

        guard let movedIndex = source.first else { return }
        let task = tasks[movedIndex]

        // Calculate the new position as midpoint between neighbors
        let actualDestination = movedIndex < destination ? destination - 1 : destination
        let newPosition: Double
        if reordered.count <= 1 {
            newPosition = 0
        } else if actualDestination == 0 {
            newPosition = (reordered[1].position ?? 1) - 1
        } else if actualDestination >= reordered.count - 1 {
            newPosition = (reordered[reordered.count - 2].position ?? Double(reordered.count - 2)) + 1
        } else {
            let before = reordered[actualDestination - 1].position ?? Double(actualDestination - 1)
            let after = reordered[actualDestination + 1].position ?? Double(actualDestination + 1)
            newPosition = (before + after) / 2
        }

        // Default view ID; ideally this would come from the project's default view
        let viewId: Int64 = 0

        Task {
            await appState.moveTask(task, toPosition: newPosition, viewId: viewId)
        }
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text("You're offline. Changes will sync when connected.")
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .listRowBackground(Color.orange.opacity(0.1))
        .accessibilityElement(children: .combine)
    }
}
