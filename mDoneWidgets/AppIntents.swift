import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Complete Task Intent

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description: IntentDescription = "Marks a task as complete in mDone"

    @Parameter(title: "Task ID")
    var taskID: Int

    init() {}

    init(taskID: Int64) {
        self.taskID = Int(taskID)
    }

    func perform() async throws -> some IntentResult {
        try await WidgetDataProvider.shared.completeTask(id: Int64(taskID))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Open Task Intent

struct OpenTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Task"
    static var description: IntentDescription = "Opens a task in mDone"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task ID")
    var taskID: Int

    init() {}

    init(taskID: Int64) {
        self.taskID = Int(taskID)
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Quick Add Intent

struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Task"
    static var description: IntentDescription = "Opens mDone to create a new task"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
