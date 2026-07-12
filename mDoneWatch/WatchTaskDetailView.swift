import SwiftUI

struct WatchTaskDetailView: View {
    let task: WidgetTask
    let onUpdate: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var priority: Int
    
    init(task: WidgetTask, onUpdate: @escaping () -> Void) {
        self.task = task
        self.onUpdate = onUpdate
        self._priority = State(initialValue: task.priority)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Título
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Descripción
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Acciones Rápidas
                Text("Acciones")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    postpone(days: 1)
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text("Posponer 1 Día")
                    }
                }
                .tint(.orange)
                .disabled(isProcessing)
                
                Button(action: {
                    postpone(days: 7)
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text("Posponer 1 Semana")
                    }
                }
                .tint(.orange)
                .disabled(isProcessing)
                
                // Selector de Prioridad
                Picker("Prioridad", selection: $priority) {
                    Text("Ninguna").tag(0)
                    Text("Normal").tag(1)
                    Text("Media").tag(2)
                    Text("Alta").tag(3)
                    Text("Urgente").tag(4)
                    Text("DO IT NOW").tag(5)
                }
                .onChange(of: priority) { newValue in
                    setPriority(newValue)
                }
                .disabled(isProcessing)
                
                Divider()
                
                Button(role: .destructive, action: {
                    deleteTask()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Eliminar")
                    }
                }
                .disabled(isProcessing)
            }
            .padding()
        }
        .navigationTitle("Detalles")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func postpone(days: Int) {
        isProcessing = true
        let currentDue = task.dueDate ?? Date()
        let newDate = currentDue.addingTimeInterval(Double(days) * 86400)
        
        Task {
            do {
                let req = WidgetDataProvider.TaskUpdateRequest(dueDate: newDate)
                try await WidgetDataProvider.shared.updateTask(id: task.id, request: req)
                DispatchQueue.main.async {
                    onUpdate()
                    dismiss()
                }
            } catch {
                print("Error posponiendo: \(error)")
                isProcessing = false
            }
        }
    }
    
    private func setPriority(_ newPriority: Int) {
        isProcessing = true
        Task {
            do {
                let req = WidgetDataProvider.TaskUpdateRequest(priority: newPriority)
                try await WidgetDataProvider.shared.updateTask(id: task.id, request: req)
                DispatchQueue.main.async {
                    onUpdate()
                    dismiss()
                }
            } catch {
                print("Error cambiando prioridad: \(error)")
                isProcessing = false
            }
        }
    }
    
    private func deleteTask() {
        isProcessing = true
        Task {
            do {
                try await WidgetDataProvider.shared.deleteTask(id: task.id)
                DispatchQueue.main.async {
                    onUpdate()
                    dismiss()
                }
            } catch {
                print("Error eliminando: \(error)")
                isProcessing = false
            }
        }
    }
    
    private func priorityString(_ priority: Int) -> String {
        switch priority {
        case 1: return "Normal"
        case 2: return "Media"
        case 3: return "Alta"
        case 4: return "Urgente"
        case 5: return "DO IT NOW"
        default: return "Ninguna"
        }
    }
}
