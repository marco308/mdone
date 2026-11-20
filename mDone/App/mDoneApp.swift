import SwiftData
import SwiftUI

@main
struct mDoneApp: App {
    private let dependencies: AppDependencies
    @State private var appState: AppState
    @State private var taskLinkRouter = TaskLinkRouter()
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var focusManager: FocusManager
    private let focusOutbox: FocusOutboxService
    #endif

    init() {
        let deps = AppDependencies()
        dependencies = deps

        // Wire the sync service before the first view appears. It used to be
        // done in `.onAppear`, which races the child views' `.task` blocks:
        // whichever refresh ran first would find no sync service and so no
        // cache to hydrate from (issue #144).
        let state = AppState()
        state.configureSyncService(
            SyncService(
                taskService: TaskService(),
                projectService: ProjectService(),
                modelContainer: deps.modelContainer
            ),
            networkMonitor: deps.networkMonitor
        )
        state.storeRecoveryMessage = deps.storeRecovery.userMessage
        _appState = State(initialValue: state)

        #if os(iOS)
        let outbox = FocusOutboxService(modelContainer: deps.modelContainer)
        focusOutbox = outbox
        _focusManager = State(initialValue: FocusManager(modelContainer: deps.modelContainer, outbox: outbox))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if AppDependencies.isHostingUnitTests {
                // The unit tests drive `AppState` and the services directly, so
                // the real UI would only add its own network traffic on top: a
                // `checkAuth()` against whatever server the simulator has
                // configured, and a `refreshAll()` on every scene-phase and
                // connectivity change, none of which any test observes. See
                // `AppDependencies.isHostingUnitTests`.
                Color.clear
            } else {
                appContent
            }
        }
    }

    private var appContent: some View {
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
        .safeAreaInset(edge: .top) {
            if taskLinkRouter.isPresented, !appState.isAuthenticated {
                HStack {
                    Text(taskLinkRouter.message ?? TaskLinkFailure.signIn.localizedDescription)
                    Button("Cancel") { taskLinkRouter.dismiss() }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: Binding(
            get: { taskLinkRouter.isPresented && appState.isAuthenticated },
            set: {
                if !$0, appState.isAuthenticated {
                    taskLinkRouter.dismiss()
                }
            }
        )) {
            LinkedTaskView(router: taskLinkRouter)
        }
        .task(id: "\(taskLinkRouter.revision)-\(appState.isAuthenticated)") {
            await taskLinkRouter.resolve(
                authenticated: appState.isAuthenticated,
                serverURL: AuthService.shared.getServerURL(),
                fetch: { try await appState.loadLinkedTask($0) }
            )
        }
        .onAppear {
            #if os(iOS)
            appState.onTaskCompleted = { taskId in
                focusManager.handleTaskCompleted(taskId: taskId)
            }
            appState.onTaskDeleted = { taskId in
                focusManager.handleTaskDeleted(taskId: taskId)
            }
            focusManager.taskLookup = { [weak appState] taskId in
                guard let appState,
                      let task = appState.tasks.first(where: { $0.id == taskId })
                else { return nil }
                return (task, appState.focusProjectName(for: task))
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
            if taskLinkRouter.receive(url) {
                return
            }
            guard url.scheme == TaskDeepLink.scheme else { return }
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
        #elseif os(macOS)
        .onOpenURL { url in
            // The widgets' Add Task links (#240). Focus has no Mac UI, so
            // mdone://focus has nothing to open here.
            if taskLinkRouter.receive(url) {
                return
            }
            guard url.scheme == TaskDeepLink.scheme, url.host == "create" else { return }
            appState.quickAddTrigger = UUID()
        }
        // Hand the URL to the open window instead of letting WindowGroup
        // spawn a second one for it.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #endif
        .environment(appState)
        .environment(dependencies.networkMonitor)
        #if os(iOS)
        .environment(focusManager)
        .environment(focusOutbox)
        #endif
        .modelContainer(dependencies.modelContainer)
    }
}
