import SwiftData
import SwiftUI

@main
struct mDoneApp: App {
    private let dependencies: AppDependencies
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var focusManager: FocusManager
    private let focusOutbox: FocusOutboxService
    #endif

    #if os(iOS)
    private let shakeDetector: ShakeDetector
    #endif

    init() {
        let deps = AppDependencies()
        dependencies = deps
        #if os(iOS)
        let outbox = FocusOutboxService(modelContainer: deps.modelContainer)
        focusOutbox = outbox
        _focusManager = State(initialValue: FocusManager(modelContainer: deps.modelContainer, outbox: outbox))
        let detector = ShakeDetector()
        detector.start()
        shakeDetector = detector
        #endif
    }

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
                .environment(focusOutbox)
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
                            await runTestAutomationIfRequested(defaults: defaults)
                        }
                    } else {
                        Task {
                            await appState.checkAuth()
                            await runTestAutomationIfRequested(defaults: defaults)
                        }
                    }
                    #else
                    Task {
                        await appState.checkAuth()
                    }
                    #endif
                }
                .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await appState.requestCalendarAccess()
                        }
                    }
                }
                .onChange(of: dependencies.networkMonitor.isConnected) { _, isConnected in
                    appState.handleConnectivityChange(isConnected: isConnected)
                    #if os(iOS)
                    if isConnected {
                        Task { await focusOutbox.drain() }
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, appState.isAuthenticated {
                        Task { await appState.refreshAll() }
                        #if os(iOS)
                        Task { await focusOutbox.drain() }
                        #endif
                    }
                }
            #if os(iOS)
                .onOpenURL { url in
                    guard url.scheme == "mdone" else { return }
                    switch url.host {
                    case "focus":
                        if focusManager.currentSession != nil {
                            focusManager.showFocusView = true
                        }
                    case "create":
                        appState.quickAddTrigger = UUID()
                    default:
                        break
                    }
                }
            #endif
        }
    }

    #if DEBUG
    /// Drives a scripted toggle for end-to-end shake-to-undo verification. Set
    /// `MDONE_AUTO_COMPLETE_TITLE` in shared defaults before a cold launch and
    /// the app will find the matching task and mark it complete. If
    /// `MDONE_TRIGGER_SHAKE_DELAY_MS` is also set, the app will post a
    /// synthetic shake notification after that delay, since the simulator
    /// has no accelerometer for CoreMotion to read.
    @MainActor
    private func runTestAutomationIfRequested(defaults: UserDefaults) async {
        guard appState.isAuthenticated else { return }
        if let title = defaults.string(forKey: "MDONE_AUTO_COMPLETE_TITLE"), !title.isEmpty {
            defaults.removeObject(forKey: "MDONE_AUTO_COMPLETE_TITLE")
            await appState.refreshAll()
            if let task = appState.tasks.first(where: { $0.title == title }) {
                await appState.toggleTaskDone(task)
            }
        }
        #if os(iOS)
        if let delayMs = defaults.object(forKey: "MDONE_TRIGGER_SHAKE_DELAY_MS") as? Int, delayMs > 0 {
            defaults.removeObject(forKey: "MDONE_TRIGGER_SHAKE_DELAY_MS")
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            NotificationCenter.default.post(name: UIWindow.deviceDidShakeNotification, object: nil)
        }
        if let delayMs = defaults.object(forKey: "MDONE_TRIGGER_UNDO_DELAY_MS") as? Int, delayMs > 0 {
            defaults.removeObject(forKey: "MDONE_TRIGGER_UNDO_DELAY_MS")
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await appState.confirmUndoLastCompletion()
        }
        #endif
    }
    #endif
}
