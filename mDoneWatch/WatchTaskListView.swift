import SwiftUI

struct WatchTaskListView: View {
    let listType: TaskListType
    
    @State private var tasks: [WidgetTask] = []
    @State private var isLoading = false
    @State private var isShowingNewTask = false
    
    var body: some View {
        List {
            if isLoading && tasks.isEmpty {
                ProgressView()
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            ForEach(tasks) { task in
                WatchTaskRow(task: task, onComplete: {
                    completeTask(task)
                }, onReload: {
                    Task { await loadData() }
                })
            }
            
            if !isLoading && tasks.isEmpty {
                Text("No hay tareas")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Button {
                isShowingNewTask = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Nueva Tarea")
                }
            }
            .foregroundStyle(.blue)
        }
        .navigationTitle(listType.title)
        .sheet(isPresented: $isShowingNewTask) {
            WatchNewTaskView(preselectedProject: projectForNewTask())
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }
    
    private func projectForNewTask() -> WidgetProject? {
        if case .project(let p) = listType {
            return p
        }
        return nil
    }
    
    private func loadData() async {
        isLoading = true
        
        do {
            switch listType {
            case .today:
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                self.tasks = data.todayTasks
            case .upcoming:
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                self.tasks = data.upcomingTasks
            case .overdue:
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                self.tasks = data.overdueTasks
            case .project(let p):
                let projectTasks = try await WidgetDataProvider.shared.fetchTasks(forProjectId: p.id)
                self.tasks = projectTasks
            }
        } catch {
            print("Error loading tasks: \(error)")
        }
        
        isLoading = false
    }
    
    private func completeTask(_ task: WidgetTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            withAnimation {
                tasks.remove(at: idx)
            }
        }
        Task {
            try? await WidgetDataProvider.shared.completeTask(id: task.id)
            _ = try? await WidgetDataProvider.shared.fetchWidgetData()
        }
    }
}
