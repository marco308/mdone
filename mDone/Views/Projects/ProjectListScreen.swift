import SwiftUI

struct ProjectListScreen: View {
    @Environment(AppState.self) private var appState

    @State private var showingCreate = false
    @State private var editingProject: Project?
    @State private var projectPendingDelete: Project?

    var body: some View {
        List {
            let favorites = appState.projects.filter { $0.isFavorite == true }
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { project in
                        projectRow(project)
                    }
                }
            }

            let regular = appState.projects.filter { $0.isFavorite != true }
            Section("Projects") {
                ForEach(regular) { project in
                    projectRow(project)
                }
            }

            Section {
                NavigationLink {
                    ArchivedProjectsScreen()
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
            }

            if appState.projects.isEmpty, !appState.isLoading {
                Section {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            icon: "folder",
                            title: "No projects",
                            subtitle: "Create your first project to organize your tasks"
                        )
                        Button {
                            showingCreate = true
                        } label: {
                            Label("New Project", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Project")
            }
        }
        .navigationDestination(for: Project.self) { project in
            TaskListScreen(projectFilter: project)
        }
        .sheet(isPresented: $showingCreate) {
            ProjectEditSheet()
        }
        .sheet(item: $editingProject) { project in
            ProjectEditSheet(project: project)
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
            Button("Archive Instead") {
                Task { await appState.archiveProject(project) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            let count = appState.tasksForProject(project.id).count
            Text(
                "This permanently deletes the project and all \(count) task\(count == 1 ? "" : "s") in it, "
                    + "including any sub-projects. This can't be undone."
            )
        }
        .refreshable {
            await appState.refreshAll()
        }
    }

    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: project) {
            ProjectRow(project: project, taskCount: appState.tasksForProject(project.id).count)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                projectPendingDelete = project
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingProject = project
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await appState.archiveProject(project) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                editingProject = project
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button {
                toggleFavorite(project)
            } label: {
                Label(
                    project.isFavorite == true ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: project.isFavorite == true ? "star.slash" : "star"
                )
            }
            Button {
                Task { await appState.archiveProject(project) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                projectPendingDelete = project
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func toggleFavorite(_ project: Project) {
        Task {
            await appState.updateProject(
                project,
                title: project.title,
                description: project.description ?? "",
                hexColor: project.hexColor ?? "",
                isFavorite: !(project.isFavorite ?? false)
            )
        }
    }
}
