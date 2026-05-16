import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget Configuration Enums

enum WidgetFontSize: String, AppEnum {
    case compact
    case standard
    case large

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Font Size"
    static var caseDisplayRepresentations: [WidgetFontSize: DisplayRepresentation] = [
        .compact: "Compact",
        .standard: "Standard",
        .large: "Large"
    ]
}

enum TodayTaskFilterMode: String, AppEnum {
    case todayAndOverdue
    case todayOnly
    case overdueOnly

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [TodayTaskFilterMode: DisplayRepresentation] = [
        .todayAndOverdue: "Today + Overdue",
        .todayOnly: "Today Only",
        .overdueOnly: "Overdue Only"
    ]
}

// MARK: - Today Widget Configuration

struct TodayWidgetSettingsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today's Tasks Settings"
    static var description = IntentDescription("Customize how today's tasks appear in this widget.")

    @Parameter(title: "Font Size", default: .standard)
    var fontSize: WidgetFontSize

    @Parameter(title: "Show", default: .todayAndOverdue)
    var filterMode: TodayTaskFilterMode

    @Parameter(title: "Tap to Complete Tasks", default: true)
    var showCompleteButton: Bool

    @Parameter(title: "Add Task Button", default: true)
    var showAddTaskButton: Bool

    init() {}
}

// MARK: - Upcoming Widget Configuration

struct UpcomingWidgetSettingsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Upcoming Tasks Settings"
    static var description = IntentDescription("Customize how upcoming tasks appear in this widget.")

    @Parameter(title: "Font Size", default: .standard)
    var fontSize: WidgetFontSize

    @Parameter(title: "Tap to Complete Tasks", default: true)
    var showCompleteButton: Bool

    @Parameter(title: "Add Task Button", default: true)
    var showAddTaskButton: Bool
}

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
        .result()
    }
}

// MARK: - Quick Add Intent

struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Task"
    static var description: IntentDescription = "Opens mDone to create a new task"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
