import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SidebarSection? = .today
    @State private var selectedTask: VTask?

    enum SidebarSection: Hashable {
        case inbox, today, upcoming, overdue, noDate
        case project(Project)
        case calendar, settings
    }

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selection: $selectedSection)
        } content: {
            MacTaskListView(section: selectedSection, selectedTask: $selectedTask)
        } detail: {
            if let task = selectedTask {
                MacTaskDetailView(task: task)
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
        .task {
            await appState.refreshAll()
        }
    }
}
