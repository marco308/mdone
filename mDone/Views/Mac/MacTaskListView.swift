import SwiftUI

struct MacTaskListView: View {
    @Environment(AppState.self) private var appState
    let section: MacContentView.SidebarSection?
    @Binding var selectedTask: VTask?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dueDate

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
        let tasks = filteredAndSortedTasks
        if tasks.isEmpty && searchText.isEmpty {
            EmptyStateView(
                icon: emptyStateIcon,
                title: emptyStateTitle,
                subtitle: emptyStateSubtitle
            )
        } else if tasks.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(tasks, selection: $selectedTask) { task in
                TaskRow(task: task)
                    .tag(task)
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Filter tasks")
            .toolbar {
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
    }

    private var sectionTitle: String {
        guard let section else { return "Tasks" }
        switch section {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .overdue: return "Overdue"
        case .noDate: return "No Date"
        case .project(let project): return project.title
        case .calendar: return "Calendar"
        case .settings: return "Settings"
        }
    }

    private var tasksForSection: [VTask] {
        guard let section else { return [] }
        switch section {
        case .inbox: return appState.activeTasks
        case .today: return appState.todayTasks
        case .upcoming: return appState.upcomingTasks
        case .overdue: return appState.overdueTasks
        case .noDate: return appState.noDateTasks
        case .project(let project): return appState.tasksForProject(project.id)
        case .calendar, .settings: return []
        }
    }

    private var filteredAndSortedTasks: [VTask] {
        var tasks = tasksForSection

        if !searchText.isEmpty {
            let query = searchText.lowercased()
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
        case .upcoming: return "calendar"
        case .overdue: return "checkmark.circle"
        case .noDate: return "tray"
        case .inbox: return "tray"
        case .project: return "folder"
        case .calendar, .settings: return "tray"
        }
    }

    private var emptyStateTitle: String {
        guard let section else { return "No Tasks" }
        switch section {
        case .today: return "All Clear Today"
        case .upcoming: return "Nothing Upcoming"
        case .overdue: return "No Overdue Tasks"
        case .noDate: return "No Undated Tasks"
        case .inbox: return "No Active Tasks"
        case .project: return "No Tasks in Project"
        case .calendar, .settings: return "No Tasks"
        }
    }

    private var emptyStateSubtitle: String {
        guard let section else { return "" }
        switch section {
        case .today: return "You have no tasks due today."
        case .upcoming: return "No tasks due this week."
        case .overdue: return "Great job staying on top of things!"
        case .noDate: return "All your tasks have due dates."
        case .inbox: return "Create a task to get started."
        case .project: return "Add a task to this project."
        case .calendar, .settings: return ""
        }
    }
}
