import SwiftUI

#if os(iOS)
extension EnvironmentValues {
    /// The task ids of the list on screen, top to bottom, set by
    /// `TaskListScreen`. A Focus Run started from a row or its detail works
    /// through the tasks after it in this order. Empty where a run makes no
    /// sense (the board, search results elsewhere), which hides the option.
    @Entry var focusRunOrder: [Int64] = []
}

extension AppState {
    /// The name a focus session shows under the task title.
    func focusProjectName(for task: VTask) -> String {
        projects.first(where: { $0.id == task.projectId })?.title ?? String(localized: "Inbox")
    }
}
#endif
