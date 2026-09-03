import AppIntents
import Foundation

// Shortcuts and Siri actions. These must stay in the app target: an intent
// with `openAppWhenRun = true` cannot run from an app extension, so when they
// lived in the widget extension every run from Shortcuts failed with
// "an internal error occurred" (#121).
//
// `AddTaskIntent` (AddTaskIntent.swift) is the hands-free one and owns the
// natural "add a task" phrases. This one opens the app with the quick-add bar
// focused, for when the user is already holding the phone.

struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Task"
    static var description: IntentDescription = "Opens mDone with the quick-add bar ready for a new task"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared?.quickAddTrigger = UUID()
        return .result()
    }
}

struct MDoneAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Add a task to \(.applicationName)",
                "New task in \(.applicationName)",
                "Add a task to \(\.$project) in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: QuickAddIntent(),
            phrases: [
                "Quick add a task in \(.applicationName)",
                "Open quick add in \(.applicationName)",
            ],
            shortTitle: "Quick Add Task",
            systemImageName: "square.and.pencil"
        )
    }
}
