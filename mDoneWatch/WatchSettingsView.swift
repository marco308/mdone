import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("defaultProjectId") private var defaultProjectId: Int = -1
    
    @AppStorage("showSwipePostpone") private var showSwipePostpone = true
    @AppStorage("showSwipePriority") private var showSwipePriority = true
    @AppStorage("showSwipeComplete") private var showSwipeComplete = true
    @AppStorage("showSwipeDelete") private var showSwipeDelete = true
    
    @State private var projects: [WidgetProject] = []
    @State private var isSyncing = false
    
    var body: some View {
        Form {
            Section(header: Text("Nueva Tarea")) {
                Picker("Proyecto Inicial", selection: $defaultProjectId) {
                    Text("Inbox / Ninguno").tag(-1)
                    ForEach(projects) { project in
                        Text(project.title).tag(Int(project.id))
                    }
                }
            }
            
            Section(header: Text("Acciones Rápidas (Deslizar)")) {
                Toggle("Posponer (+1 Día)", isOn: $showSwipePostpone)
                Toggle("Cambiar Prioridad", isOn: $showSwipePriority)
                Toggle("Marcar Completado", isOn: $showSwipeComplete)
                Toggle("Eliminar Tarea", isOn: $showSwipeDelete)
            }
            
            Section {
                Button(action: forceSync) {
                    HStack {
                        Text("Sincronizar Ahora")
                        Spacer()
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                .disabled(isSyncing)
            }
        }
        .navigationTitle("Ajustes")
        .onAppear {
            if let cached = WidgetDataProvider.shared.cachedWidgetData() {
                self.projects = cached.projects
            }
        }
    }
    
    private func forceSync() {
        isSyncing = true
        Task {
            do {
                _ = try await WidgetDataProvider.shared.fetchWidgetData()
                if let cached = WidgetDataProvider.shared.cachedWidgetData() {
                    DispatchQueue.main.async {
                        self.projects = cached.projects
                    }
                }
            } catch {
                print("Error syncing: \(error)")
            }
            DispatchQueue.main.async {
                isSyncing = false
            }
        }
    }
}
