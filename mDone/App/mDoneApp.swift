import SwiftUI
import SwiftData

@main
struct mDoneApp: App {
    private let dependencies = AppDependencies()
    @State private var appState = AppState()

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
            .modelContainer(dependencies.modelContainer)
            .onAppear {
                appState.checkAuth()
            }
        }
    }
}
