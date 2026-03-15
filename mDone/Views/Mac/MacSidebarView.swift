import SwiftUI

struct MacSidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: MacContentView.SidebarSection?

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

            Section("Projects") {
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
                    }
                    .tag(MacContentView.SidebarSection.project(project))
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

                Label("Calendar", systemImage: "calendar")
                    .tag(MacContentView.SidebarSection.calendar)

                Label("Settings", systemImage: "gear")
                    .tag(MacContentView.SidebarSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .navigationTitle("mDone")
    }

    private func projectColor(_ project: Project) -> Color {
        guard let hex = project.hexColor, !hex.isEmpty else { return Color.accentColor }
        return Color(hex: hex)
    }
}
