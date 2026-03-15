import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SidebarSection? = .today
    @State private var selectedTask: VTask?

    enum SidebarSection: Hashable {
        case inbox, today, upcoming, overdue, noDate
        case project(Project)
        case notifications, calendar, settings
    }

    /// Sections that display a task list (and thus support task selection in the detail pane).
    private var sectionShowsTaskList: Bool {
        guard let selectedSection else { return false }
        switch selectedSection {
        case .inbox, .today, .upcoming, .overdue, .noDate, .project:
            return true
        case .notifications, .calendar, .settings:
            return false
        }
    }

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selection: $selectedSection)
        } content: {
            MacTaskListView(section: selectedSection, selectedTask: $selectedTask)
        } detail: {
            if sectionShowsTaskList, let task = selectedTask {
                MacTaskDetailView(task: task)
                    .id(task.id)
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "checkmark.circle",
                    description: Text("Choose a task to view its details")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        .frame(minWidth: 900, minHeight: 600)
        .macKeyboardShortcuts()
        .onChange(of: selectedSection) { _, newSection in
            // Clear task selection when switching to a non-task-list section
            if let newSection {
                switch newSection {
                case .notifications, .calendar, .settings:
                    selectedTask = nil
                default:
                    break
                }
            }
        }
        .task {
            await appState.refreshAll()
            await appState.fetchNotifications()
        }
    }
}
