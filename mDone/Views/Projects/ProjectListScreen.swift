import SwiftUI

struct ProjectListScreen: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            let favorites = appState.projects.filter { $0.isFavorite == true }
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project, taskCount: appState.tasksForProject(project.id).count)
                        }
                    }
                }
            }

            let regular = appState.projects.filter { $0.isFavorite != true }
            Section("Projects") {
                ForEach(regular) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project, taskCount: appState.tasksForProject(project.id).count)
                    }
                }
            }

            if appState.projects.isEmpty && !appState.isLoading {
                Section {
                    EmptyStateView(
                        icon: "folder",
                        title: "No projects",
                        subtitle: "Create projects in your Vikunja instance"
                    )
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Projects")
        .navigationDestination(for: Project.self) { project in
            TaskListScreen(projectFilter: project)
        }
        .refreshable {
            await appState.refreshAll()
        }
    }
}
