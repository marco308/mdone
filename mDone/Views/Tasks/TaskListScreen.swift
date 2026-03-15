import SwiftUI

struct TaskListScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    var projectFilter: Project? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                if !networkMonitor.isConnected {
                    offlineBanner
                }

                if let projectFilter {
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
                        }
                    }
                } else {
                    smartListSections
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await appState.refreshAll()
            }

            QuickAddBar(projectId: projectFilter?.id ?? defaultProjectId)
        }
        .navigationTitle(projectFilter?.title ?? "Inbox")
        .overlay {
            if appState.isLoading && appState.tasks.isEmpty {
                LoadingOverlay()
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

        if !appState.upcomingTasks.isEmpty {
            SmartListSection(
                title: "Upcoming",
                tasks: appState.upcomingTasks,
                accentColor: .blue
            )
        }

        if !appState.noDateTasks.isEmpty {
            SmartListSection(
                title: "No Date",
                tasks: appState.noDateTasks,
                accentColor: .secondary
            )
        }

        if appState.activeTasks.isEmpty && !appState.isLoading {
            Section {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All done!",
                    subtitle: "No pending tasks"
                )
            }
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
