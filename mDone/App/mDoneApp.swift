import SwiftData
import SwiftUI

@main
struct mDoneApp: App {
    private let dependencies = AppDependencies()
    @State private var appState = AppState()
    #if os(iOS)
    @State private var focusManager = FocusManager()
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    #if os(iOS)
                    MainTabView()
                    #else
                    MacContentView()
                    #endif
                } else {
                    ServerSetupView()
                }
            }
            .environment(appState)
            .environment(dependencies.networkMonitor)
            #if os(iOS)
            .environment(focusManager)
            #endif
            .modelContainer(dependencies.modelContainer)
            .onAppear {
                let syncService = SyncService(
                    taskService: TaskService(),
                    projectService: ProjectService(),
                    modelContainer: dependencies.modelContainer
                )
                appState.configureSyncService(syncService, networkMonitor: dependencies.networkMonitor)

                #if os(iOS)
                appState.onTaskCompleted = { taskId in
                    focusManager.handleTaskCompleted(taskId: taskId)
                }
                appState.onTaskDeleted = { taskId in
                    focusManager.handleTaskDeleted(taskId: taskId)
                }
                #endif

                #if DEBUG
                // Support auto-login via UserDefaults for testing (set via simctl)
                let defaults = UserDefaults.standard
                if !appState.isAuthenticated,
                   let serverURL = defaults.string(forKey: "MDONE_SERVER_URL"),
                   let token = defaults.string(forKey: "MDONE_TOKEN"),
                   !serverURL.isEmpty, !token.isEmpty
                {
                    defaults.removeObject(forKey: "MDONE_SERVER_URL")
                    defaults.removeObject(forKey: "MDONE_TOKEN")
                    Task {
                        try? await appState.login(serverURL: serverURL, token: token)
                    }
                } else {
                    Task {
                        await appState.checkAuth()
                    }
                }
                #else
                Task {
                    await appState.checkAuth()
                }
                #endif
            }
            .onChange(of: dependencies.networkMonitor.isConnected) { _, isConnected in
                appState.handleConnectivityChange(isConnected: isConnected)
            }
            #if os(iOS)
            .onOpenURL { url in
                if url.scheme == "mdone", url.host == "focus" {
                    focusManager.showFocusView = true
                }
            }
            #endif
        }
    }
}
