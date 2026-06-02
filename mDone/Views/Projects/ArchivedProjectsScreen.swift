import SwiftUI

/// Lists archived projects with Unarchive / Delete actions. Read-only: tapping a
/// project opens its task list without the quick-add bar.
struct ArchivedProjectsScreen: View {
    @Environment(AppState.self) private var appState
    @State private var projectPendingDelete: Project?

    var body: some View {
        List {
            if appState.archivedProjects.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "No archived projects",
                        subtitle: "Projects you archive will appear here"
                    )
                }
            } else {
                ForEach(appState.archivedProjects) { project in
                    NavigationLink {
                        TaskListScreen(projectFilter: project, readOnly: true)
                    } label: {
                        ProjectRow(project: project, taskCount: appState.tasksForProject(project.id).count)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            projectPendingDelete = project
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            Task { await appState.unarchiveProject(project) }
                        } label: {
                            Label("Unarchive", systemImage: "arrow.uturn.up")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            Task { await appState.unarchiveProject(project) }
                        } label: {
                            Label("Unarchive", systemImage: "arrow.uturn.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            projectPendingDelete = project
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Archived")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await appState.fetchArchivedProjects()
            }
            .refreshable {
                await appState.fetchArchivedProjects()
            }
            .confirmationDialog(
                "Delete \(projectPendingDelete?.title ?? "")?",
                isPresented: Binding(
                    get: { projectPendingDelete != nil },
                    set: { if !$0 { projectPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: projectPendingDelete
            ) { project in
                Button("Delete Project", role: .destructive) {
                    Task { await appState.deleteProject(project) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(
                    "This permanently deletes the project and all of its tasks, including any sub-projects. This can't be undone."
                )
            }
    }
}
