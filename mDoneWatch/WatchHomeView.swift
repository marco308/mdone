import SwiftUI

enum TaskListType: Hashable {
    case today
    case overdue
    case upcoming
    case project(WidgetProject)
    
    var title: String {
        switch self {
        case .today: return "Hoy"
        case .overdue: return "Atrasado"
        case .upcoming: return "Próximos"
        case .project(let p): return p.title
        }
    }
}

struct WatchHomeView: View {
    @State private var projects: [WidgetProject] = []
    @State private var todayCount: Int = 0
    @State private var overdueCount: Int = 0
    @State private var upcomingCount: Int = 0
    @State private var isShowingNewTask = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: TaskListType.today) {
                        HStack {
                            Image(systemName: "calendar.day.timeline.left")
                                .foregroundStyle(.blue)
                            Text("Hoy")
                            Spacer()
                            if todayCount > 0 {
                                Text("\(todayCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink(value: TaskListType.overdue) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                            Text("Atrasado")
                            Spacer()
                            if overdueCount > 0 {
                                Text("\(overdueCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink(value: TaskListType.upcoming) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.orange)
                            Text("Próximos")
                            Spacer()
                            if upcomingCount > 0 {
                                Text("\(upcomingCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if !projects.isEmpty {
                    Section(header: Text("Mis Proyectos")) {
                        ForEach(projects) { project in
                            NavigationLink(value: TaskListType.project(project)) {
                                HStack {
                                    Image(systemName: "list.bullet")
                                        .foregroundStyle(project.parsedColor ?? .accentColor)
                                    Text(project.title)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    NavigationLink(destination: WatchSettingsView()) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Ajustes")
                        }
                    }
                }
            }
            .navigationTitle("mDone")
            .navigationDestination(for: TaskListType.self) { listType in
                WatchTaskListView(listType: listType)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingNewTask) {
                WatchNewTaskView(preselectedProject: nil)
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        // First load from cache for instant UI
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            updateCounts(from: cached)
        }
        
        // Then fetch latest
        do {
            let data = try await WidgetDataProvider.shared.fetchWidgetData()
            updateCounts(from: data)
        } catch {
            print("Error loading home data: \(error)")
        }
    }
    
    private func updateCounts(from data: WidgetData) {
        DispatchQueue.main.async {
            self.todayCount = data.todayTasks.count
            self.overdueCount = data.overdueTasks.count
            self.upcomingCount = data.upcomingTasks.count
            self.projects = data.projects
        }
    }
}
