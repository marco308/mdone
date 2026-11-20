import SwiftUI

struct LinkedTaskView: View {
    @Environment(AppState.self) private var appState
    let router: TaskLinkRouter

    var body: some View {
        Group {
            if let task = router.task {
                #if os(iOS)
                TaskDetailSheet(task: task, showsCompletionAction: true)
                    .id(task.id)
                #else
                NavigationStack {
                    MacTaskDetailView(task: appState.tasks.first(where: { $0.id == task.id }) ?? task)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { router.dismiss() }
                            }
                        }
                }
                .frame(minWidth: 550, minHeight: 600)
                #endif
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if router.isLoading {
                            ProgressView("Opening task…")
                        } else {
                            Text(router.message ?? String(localized: "Opening task…"))
                                .multilineTextAlignment(.center)
                            if router.request != nil {
                                Button("Retry") { router.retry() }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Open Task")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { router.dismiss() }
                        }
                    }
                }
            }
        }
        .errorBanner(Bindable(appState).activeError)
    }
}
