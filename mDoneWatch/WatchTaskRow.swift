import SwiftUI

struct WatchTaskRow: View {
    let task: WidgetTask
    let onComplete: () -> Void
    let onReload: () -> Void
    
    @State private var isCompleted = false
    
    @AppStorage("showSwipePostpone") private var showSwipePostpone = true
    @AppStorage("showSwipePriority") private var showSwipePriority = true
    @AppStorage("showSwipeComplete") private var showSwipeComplete = true
    @AppStorage("showSwipeDelete") private var showSwipeDelete = true
    
    var body: some View {
        NavigationLink(destination: WatchTaskDetailView(task: task, onUpdate: onReload)) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.snappy) {
                        isCompleted = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isCompleted ? .green : (task.parsedColor ?? task.priorityColor))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                    
                    if let dueDate = task.dueDate {
                        Text(dueDate, style: .time)
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue && !isCompleted ? .red : .secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: showSwipeDelete) {
            if showSwipeDelete {
                Button(role: .destructive) {
                    deleteTask()
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
            if showSwipeComplete {
                Button {
                    withAnimation { isCompleted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                } label: {
                    Label("Completar", systemImage: "checkmark")
                }
                .tint(.green)
            }
            if showSwipePriority {
                Button {
                    cyclePriority()
                } label: {
                    Label("Prioridad", systemImage: "exclamationmark.3")
                }
                .tint(.blue)
            }
            if showSwipePostpone {
                Button {
                    postponeTask()
                } label: {
                    Label("Posponer", systemImage: "calendar.badge.clock")
                }
                .tint(.orange)
            }
        }
    }
    
    private func cyclePriority() {
        Task {
            do {
                let current = task.priority
                let next = current >= 5 ? 1 : current + 1
                let req = WidgetDataProvider.TaskUpdateRequest(priority: next)
                try await WidgetDataProvider.shared.updateTask(id: task.id, request: req)
                DispatchQueue.main.async {
                    onReload()
                }
            } catch {
                print("Error cambiando prioridad: \(error)")
            }
        }
    }
    
    private func postponeTask() {
        Task {
            do {
                let currentDue = task.dueDate ?? Date()
                let newDate = currentDue.addingTimeInterval(86400)
                let req = WidgetDataProvider.TaskUpdateRequest(dueDate: newDate)
                try await WidgetDataProvider.shared.updateTask(id: task.id, request: req)
                DispatchQueue.main.async {
                    onReload()
                }
            } catch {
                print("Error posponiendo: \(error)")
            }
        }
    }
    
    private func deleteTask() {
        Task {
            do {
                try await WidgetDataProvider.shared.deleteTask(id: task.id)
                DispatchQueue.main.async {
                    onReload()
                }
            } catch {
                print("Error eliminando: \(error)")
            }
        }
    }
}
