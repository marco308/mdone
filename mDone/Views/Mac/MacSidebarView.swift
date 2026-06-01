import SwiftUI

struct MacSidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: MacContentView.SidebarSection?

    @State private var showingCreate = false
    @State private var editingProject: Project?
    @State private var projectPendingDelete: Project?

    var body: some View {
        List(selection: $selection) {
            Section("Smart Lists") {
                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        if !appState.activeTasks.isEmpty {
                            Text("\(appState.activeTasks.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "tray")
                        .foregroundStyle(.indigo)
                }
                .tag(MacContentView.SidebarSection.inbox)

                Label {
                    HStack {
                        Text("Today")
                        Spacer()
                        if !appState.todayTasks.isEmpty {
                            Text("\(appState.todayTasks.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "calendar.day.timeline.left")
                        .foregroundStyle(.blue)
                }
                .tag(MacContentView.SidebarSection.today)

                Label {
                    HStack {
                        Text("Tomorrow")
                        Spacer()
                        if !appState.tomorrowTasks.isEmpty {
                            Text("\(appState.tomorrowTasks.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "sunrise")
                        .foregroundStyle(.orange)
                }
                .tag(MacContentView.SidebarSection.tomorrow)

                Label {
                    HStack {
                        Text("This Week")
                        Spacer()
                        if !appState.thisWeekTasks.isEmpty {
                            Text("\(appState.thisWeekTasks.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.blue)
                }
                .tag(MacContentView.SidebarSection.thisWeek)

                Label {
                    Text("Upcoming")
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.purple)
                }
                .tag(MacContentView.SidebarSection.upcoming)

                Label {
                    HStack {
                        Text("Overdue")
                        Spacer()
                        if !appState.overdueTasks.isEmpty {
                            Text("\(appState.overdueTasks.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                .tag(MacContentView.SidebarSection.overdue)

                Label {
                    Text("No Date")
                } icon: {
                    Image(systemName: "tray")
                        .foregroundStyle(.gray)
                }
                .tag(MacContentView.SidebarSection.noDate)
            }

            Section {
                ForEach(appState.projects) { project in
                    Label {
                        HStack {
                            Text(project.title)
                            Spacer()
                            let count = appState.tasksForProject(project.id).count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Circle()
                            .fill(projectColor(project))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                    }
                    .tag(MacContentView.SidebarSection.project(project))
                    .contextMenu { projectContextMenu(project) }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Project")
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .accessibilityLabel("New Project")
                }
            }

            Section {
                Label {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        if appState.unreadNotificationCount > 0 {
                            Text("\(appState.unreadNotificationCount)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                }
                .tag(MacContentView.SidebarSection.notifications)

                Label {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        if appState.calendarAccessGranted, !appState.todayCalendarEvents.isEmpty {
                            Text("\(appState.todayCalendarEvents.count)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
                .tag(MacContentView.SidebarSection.calendar)

                Label("Archived", systemImage: "archivebox")
                    .tag(MacContentView.SidebarSection.archived)

                Label("Settings", systemImage: "gear")
                    .tag(MacContentView.SidebarSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .navigationTitle("mDone")
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
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button {
            editingProject = project
        } label: {
            Label("Edit…", systemImage: "pencil")
        }
        Button {
            Task {
                await appState.updateProject(
                    project,
                    title: project.title,
                    description: project.description ?? "",
                    hexColor: project.hexColor ?? "",
                    isFavorite: !(project.isFavorite ?? false)
                )
            }
        } label: {
            Label(
                project.isFavorite == true ? "Remove from Favourites" : "Add to Favourites",
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

    private func projectColor(_ project: Project) -> Color {
        guard let hex = project.hexColor, !hex.isEmpty else { return Color.accentColor }
        return Color(hex: hex)
    }
}
