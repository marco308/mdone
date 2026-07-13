import SwiftUI

/// Content-column view listing archived projects on macOS, with Unarchive / Delete
/// actions. Shown when the "Archived" sidebar item is selected.
struct MacArchivedProjectsView: View {
    @Environment(AppState.self) private var appState
    @State private var projectPendingDelete: Project?

    var body: some View {
        Group {
            if appState.archivedProjects.isEmpty {
                ContentUnavailableView(
                    "No Archived Projects",
                    systemImage: "archivebox",
                    description: Text("Projects you archive will appear here")
                )
            } else {
                List {
                    ForEach(appState.archivedProjects) { project in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(projectColor(project))
                                .frame(width: 10, height: 10)
                            Text(project.title)
                            Spacer()
                            Button("Unarchive") {
                                Task { await appState.unarchiveProject(project) }
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                projectPendingDelete = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .task {
            await appState.fetchArchivedProjects()
        }
        .confirmationDialog(
            "Delete \(projectPendingDelete?.title ?? "")?",
            isPresented: Binding(
                get: { projectPendingDelete != nil },
                set: {
                    if !$0 {
                        projectPendingDelete = nil
                    }
                }
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

    private func projectColor(_ project: Project) -> Color {
        guard let hex = project.hexColor, !hex.isEmpty else { return Color.accentColor }
        return Color(hex: hex)
    }
}
