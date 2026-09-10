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
    @AppStorage("calmMode") private var calmMode = false
    #if os(iOS)
    /// `nil` until the board toggle is tapped: until then the screen shows
    /// whatever `ProjectViewPreference` remembers for this project (#184).
    @State private var boardOverride: Bool?
    /// On iPad, a task opens in a pane beside the list when there is room;
    /// see `InlineTaskSelection`. Held here so Inbox and each project screen
    /// keep their own selection.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var inlineSelection = InlineTaskSelection()
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
        return boardVisible
        #else
        return false
        #endif
    }

    #if os(iOS)
    /// Whether the board is on screen: this visit's choice once the toggle has
    /// been tapped, else the view remembered for this project, else the
    /// default from Settings. A project with no Kanban view always shows the
    /// list, whatever is stored.
    private var boardVisible: Bool {
        guard boardAvailable, let projectFilter else { return false }
        return boardOverride ?? (ProjectViewPreference.mode(for: projectFilter.id) == .board)
    }

    /// Switches view and remembers the choice for this project, so the next
    /// visit opens the same way (#184).
    private func setBoardVisible(_ visible: Bool) {
        boardOverride = visible
        if let projectFilter {
            ProjectViewPreference.save(visible ? .board : .list, for: projectFilter.id)
        }
    }
    #endif

    private var sortScope: TaskSortScope {
        projectFilter.map { .project($0.id) } ?? .inbox
    }

    private var sortPreference: TaskSortPreference {
        appState.sortPreference(for: sortScope)
    }

    /// Rows can only be dragged when the list shows the server's order;
    /// under any other sort the drop would be sorted straight back.
    private var manualOrderActive: Bool {
        projectFilter != nil && sortPreference.order == .manual
    }

    var body: some View {
        @Bindable var bindableAppState = appState
        adaptiveContent
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
            .navigationTitle(projectFilter?.title ?? String(localized: "Inbox"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: projectFilter?.id) { _, _ in
                boardOverride = nil
            }
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

    /// The list (or board) alone on iPhone; on iPad with room, the same beside
    /// the selected task's detail pane. The size is read here, not at the
    /// row, because Split View and Stage Manager can resize the window with
    /// the list on screen: the pane then gives way and taps go back to
    /// opening a sheet (issue #34).
    @ViewBuilder
    private var adaptiveContent: some View {
        #if os(iOS)
        GeometryReader { geometry in
            let showsPane = InlineTaskDetailLayout.showsPane(
                isRegularWidth: horizontalSizeClass == .regular,
                containerWidth: geometry.size.width
            )
            HStack(spacing: 0) {
                content
                    .environment(showsPane ? inlineSelection : nil)

                if showsPane, let task = inlineTask {
                    Divider()
                    TaskDetailSheet(task: task, presentation: .inline { inlineSelection.task = nil })
                        // Fresh editing state per task; without this the
                        // pane would keep the previous task's edits.
                        .id(task.id)
                        .frame(width: InlineTaskDetailLayout.paneWidth(for: geometry.size.width))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsPane && inlineTask != nil)
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    /// The task to show in the pane: the live copy from `AppState` when it
    /// has one, so edits made from the row are reflected, else the snapshot
    /// the row was tapped with (board cards can carry tasks the main list
    /// does not hold).
    private var inlineTask: VTask? {
        guard let selected = inlineSelection.task else { return nil }
        return appState.tasks.first(where: { $0.id == selected.id }) ?? selected
    }
    #endif

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if boardVisible, let projectFilter {
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

                    if isOffline {
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
                                    title: String(localized: "No tasks"),
                                    subtitle: String(localized: "Add a task to get started")
                                )
                            }
                        } else {
                            let rows = TaskNesting.rows(for: projectTasks)
                            let hasNesting = rows.contains { $0.depth > 0 }
                            Section {
                                // Single ForEach for flat and nested display so
                                // row identity survives the list gaining/losing
                                // nesting (else a presented detail sheet gets
                                // dismissed when the first subtask is linked).
                                // Reorder is flat-only and manual-sort-only;
                                // when flat, `rows` preserves `projectTasks`'
                                // order so the move indices line up.
                                ForEach(rows) { row in
                                    TaskRow(task: row.task, readOnly: readOnly, indentLevel: row.depth)
                                        .moveDisabled(readOnly || hasNesting || !manualOrderActive)
                                }
                                .onMove { source, destination in
                                    handleMove(tasks: projectTasks, from: source, to: destination)
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
                    setBoardVisible(!boardVisible)
                } label: {
                    Image(systemName: boardVisible ? "list.bullet" : "rectangle.split.3x1")
                }
                .accessibilityLabel(boardVisible ? "Show list" : "Show board")
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
                TaskSortMenu(scope: sortScope)
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
                    title: String(localized: "No results"),
                    subtitle: String(localized: "Try a different search or filter")
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
                title: String(localized: "Current"),
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
                    title: String(localized: "Today"),
                    tasks: sorted(todayAndOverdue),
                    accentColor: Color.accentColor
                )
            }
        } else {
            let overdue = excludingCurrent(appState.overdueTasks, currentIds: currentIds)
            if !overdue.isEmpty {
                SmartListSection(
                    title: String(localized: "Overdue"),
                    tasks: sorted(overdue),
                    accentColor: .red
                )
            }

            let today = excludingCurrent(appState.todayTasks, currentIds: currentIds)
            if !today.isEmpty {
                SmartListSection(
                    title: String(localized: "Today"),
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
                title: String(localized: "Tomorrow"),
                tasks: sorted(tomorrow),
                accentColor: .orange
            )
        }

        let thisWeek = excludingCurrent(appState.thisWeekTasks, currentIds: currentIds)
        if !thisWeek.isEmpty {
            SmartListSection(
                title: String(localized: "This Week"),
                tasks: sorted(thisWeek),
                accentColor: .blue
            )
        }

        let upcoming = excludingCurrent(appState.upcomingTasks, currentIds: currentIds)
        if !upcoming.isEmpty {
            SmartListSection(
                title: String(localized: "Upcoming"),
                tasks: sorted(upcoming),
                accentColor: .purple
            )
        }

        let noDate = excludingCurrent(appState.noDateTasks, currentIds: currentIds)
        if !noDate.isEmpty {
            SmartListSection(
                title: String(localized: "No Date"),
                tasks: sorted(noDate),
                accentColor: .secondary
            )
        }

        if appState.activeTasks.isEmpty, !appState.isLoading {
            Section {
                // An empty list while offline usually means "nothing cached
                // yet", not "nothing to do". Claiming "All done!" there is
                // actively misleading (issue #144).
                if isOffline {
                    EmptyStateView(
                        icon: "wifi.slash",
                        title: String(localized: "No cached tasks"),
                        subtitle: String(localized: "Connect to your server to load your tasks")
                    )
                } else {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: String(localized: "All done!"),
                        subtitle: String(localized: "No pending tasks")
                    )
                }
            }
        }
    }

    /// Removes tasks already shown in the Current section so they don't appear
    /// twice in the date-based sections below it.
    private func excludingCurrent(_ tasks: [VTask], currentIds: Set<Int64>) -> [VTask] {
        currentIds.isEmpty ? tasks : tasks.filter { !currentIds.contains($0.id) }
    }

    private func sorted(_ tasks: [VTask]) -> [VTask] {
        sortPreference.apply(to: tasks)
    }

    private func handleMove(tasks: [VTask], from source: IndexSet, to destination: Int) {
        guard let move = TaskPositioning.move(tasks, fromOffsets: source, toOffset: destination) else { return }
        Task {
            await appState.moveTask(move.task, toPosition: move.position, newOrder: move.reordered)
        }
    }

    /// True when the device has no link, or when the last refresh couldn't
    /// reach the server on an otherwise-working connection (a self-hosted
    /// Vikunja behind a VPN that's down, say). The second case looks identical
    /// to the user, so it gets the same banner.
    private var isOffline: Bool {
        !networkMonitor.isConnected || appState.isShowingCachedData
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text(offlineBannerText)
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .listRowBackground(Color.orange.opacity(0.1))
        .accessibilityElement(children: .combine)
    }

    /// Says what's actually happening: whether the user is just reading cached
    /// data, or has edits sitting in the queue waiting to go out.
    private var offlineBannerText: String {
        let pending = appState.pendingOperationsCount
        guard pending > 0 else {
            return String(localized: "You're offline. Showing your last synced tasks.")
        }
        // One key with a plural variation in the catalog rather than a
        // hand-rolled singular/plural ternary: languages vary in how many
        // plural forms they have, and only the catalog can express that.
        return String(localized: "You're offline. \(pending) changes will sync when you reconnect.")
    }
}
