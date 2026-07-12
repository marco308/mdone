import SwiftUI

struct WatchNewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultProjectId") private var defaultProjectId: Int = -1
    
    let preselectedProject: WidgetProject?
    
    @State private var taskTitle: String = ""
    @State private var selectedProjectId: Int = -1
    @State private var projects: [WidgetProject] = []
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        Form {
            Section {
                TextField("Nueva tarea...", text: $taskTitle)
            }
            
            Section {
                Picker("Proyecto", selection: $selectedProjectId) {
                    if selectedProjectId == -1 {
                        Text("Seleccionar...").tag(-1)
                    }
                    ForEach(projects) { project in
                        Text(project.title).tag(Int(project.id))
                    }
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            
            Section {
                Button(action: saveTask) {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Guardar")
                        }
                        Spacer()
                    }
                }
                .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProjectId == -1 || isSaving)
                .foregroundStyle(.green)
            }
        }
        .navigationTitle("Crear Tarea")
        .onAppear {
            if let cached = WidgetDataProvider.shared.cachedWidgetData() {
                self.projects = cached.projects
                
                if let pre = preselectedProject {
                    selectedProjectId = Int(pre.id)
                } else if defaultProjectId != -1 {
                    selectedProjectId = defaultProjectId
                } else if let first = projects.first {
                    selectedProjectId = Int(first.id)
                }
            }
        }
    }
    
    private func saveTask() {
        guard !taskTitle.isEmpty, selectedProjectId != -1 else { return }
        
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                try await WidgetDataProvider.shared.createTask(title: taskTitle, projectId: Int64(selectedProjectId))
                
                // Refresh data
                _ = try? await WidgetDataProvider.shared.fetchWidgetData()
                
                DispatchQueue.main.async {
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
