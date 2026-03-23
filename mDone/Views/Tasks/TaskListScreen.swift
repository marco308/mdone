import SwiftUI

struct TaskListScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    var projectFilter: Project?
    @State private var showAdvancedFilter = false

    var body: some View {
        @Bindable var bindableAppState = appState
        ZStack(alignment: .bottom) {
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
                        let projectTasks = appState.tasksForProject(projectFilter.id)
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
                                ForEach(projectTasks) { task in
                                    TaskRow(task: task)
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

            QuickAddBar(
                projectId: projectFilter?.id ?? defaultProjectId,
                defaultDueDate: projectFilter == nil ? Calendar.current.startOfDay(for: Date()) : nil
            )
        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdvancedFilter = true
                } label: {
                    Image(systemName: appState.advancedFilterString != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
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

    private var isFiltering: Bool {
        !appState.searchQuery.isEmpty || appState.activeFilter != nil
    }

    @ViewBuilder
    private var filteredTaskSection: some View {
        let allFiltered = appState.filteredTasks
        let tasks = if let projectFilter {
            allFiltered.filter { $0.projectId == projectFilter.id }
        } else {
            allFiltered
        }
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
        if !appState.overdueTasks.isEmpty {
            SmartListSection(
                title: "Overdue",
                tasks: appState.overdueTasks,
                accentColor: .red
            )
        }

        if !appState.todayTasks.isEmpty {
            SmartListSection(
                title: "Today",
                tasks: appState.todayTasks,
                accentColor: Color.accentColor
            )
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

        if !appState.tomorrowTasks.isEmpty {
            SmartListSection(
                title: "Tomorrow",
                tasks: appState.tomorrowTasks,
                accentColor: .orange
            )
        }

        if !appState.thisWeekTasks.isEmpty {
            SmartListSection(
                title: "This Week",
                tasks: appState.thisWeekTasks,
                accentColor: .blue
            )
        }

        if !appState.upcomingTasks.isEmpty {
            SmartListSection(
                title: "Upcoming",
                tasks: appState.upcomingTasks,
                accentColor: .purple
            )
        }

        if !appState.noDateTasks.isEmpty {
            SmartListSection(
                title: "No Date",
                tasks: appState.noDateTasks,
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
            Text("You're offline. Changes will sync when connected.")
                .font(.caption)
        }
        .foregroundStyle(.orange)
        .listRowBackground(Color.orange.opacity(0.1))
    }
}
