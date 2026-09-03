import AppIntents
import Foundation

// "Hey Siri, add a task in mDone." Runs in the background, so it works where
// there is no screen to hand over to: on the steering wheel over CarPlay, on
// AirPods, on the Watch. That is also why it must never set `openAppWhenRun`:
// Siri would try to bring the phone UI forward and fail. The quick-add
// shortcut in AppIntents.swift is the on-screen variant.
//
// App Shortcut phrases can only embed enum or entity parameters, never free
// text, so the title cannot be part of the phrase. Siri asks for it with
// `requestValueDialog` instead, which is the usual two-step for hands-free
// capture.

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription(
        "Adds a task to mDone without opening the app. If you're offline the task is kept and sent when you reconnect."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task", requestValueDialog: "What's the task?")
    var taskTitle: String

    @Parameter(title: "Project")
    var project: ProjectEntity?

    /// Optional so Siri never asks for it. Left empty, the task falls due
    /// according to Settings > Tasks > "Siri adds tasks due" (today at the
    /// default due time unless changed).
    @Parameter(title: "Due date")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to \(\.$project)") {
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = AppState.shared else { throw IntentTaskError.notSignedIn }
        let outcome = try await state.createTaskFromIntent(
            title: taskTitle,
            projectId: project?.projectId,
            dueDate: dueDate ?? SiriDueDatePreference.dueDate()
        )
        return .result(dialog: IntentDialog("\(Self.dialog(for: outcome))"))
    }

    /// What Siri says back. Spoken as well as shown, so it names the task,
    /// the project and the due date: in the car that is the only
    /// confirmation the user gets.
    static func dialog(for outcome: IntentTaskOutcome) -> String {
        switch outcome {
        case let .created(taskTitle, projectTitle, dueDate):
            if let dueDate {
                String(localized: "Added \"\(taskTitle)\" to \(projectTitle), due \(dueText(dueDate)).")
            } else {
                String(localized: "Added \"\(taskTitle)\" to \(projectTitle).")
            }
        case let .queued(taskTitle, projectTitle, dueDate):
            if let dueDate {
                String(
                    localized: "Added \"\(taskTitle)\" to \(projectTitle), due \(dueText(dueDate)). It will sync when you're back online."
                )
            } else {
                String(localized: "Added \"\(taskTitle)\" to \(projectTitle). It will sync when you're back online.")
            }
        }
    }

    /// "Today at 6:00 PM", "Tomorrow at 9:00 AM", or a short date for anything
    /// further out. Foundation localizes the relative words.
    static func dueText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// How a task created from outside the UI ended up.
enum IntentTaskOutcome: Equatable {
    /// Reached the server; the task exists there with an id.
    case created(taskTitle: String, projectTitle: String, dueDate: Date?)
    /// No connection; queued for replay when one returns.
    case queued(taskTitle: String, projectTitle: String, dueDate: Date?)
}

/// Failures the intent reports back through Siri. The wording is spoken, so
/// each case says what the user can do about it.
enum IntentTaskError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case emptyTitle
    case noProject
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            "Open mDone and sign in to your Vikunja server first."
        case .emptyTitle:
            "The task needs a title."
        case .noProject:
            "mDone has no project to add the task to. Open the app once to load your projects."
        case let .failed(message):
            "\(message)"
        }
    }
}

/// A Vikunja project as Siri and Shortcuts see it, so a phrase like "Add a
/// task to Home in mDone" resolves against the user's own project names.
struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = ProjectEntityQuery()

    /// `Project.id` as a string, which is what App Intents needs an identifier to be.
    let id: String
    let projectId: Int64
    let title: String

    init(project: Project) {
        id = String(project.id)
        projectId = project.id
        title = project.title
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct ProjectEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let ids = Set(identifiers.compactMap { Int64($0) })
        return await Self.projects().filter { ids.contains($0.id) }.map(ProjectEntity.init(project:))
    }

    func entities(matching string: String) async throws -> [ProjectEntity] {
        await Self.projects()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(ProjectEntity.init(project:))
    }

    /// Siri's vocabulary for the project phrase. `AppState` asks the system to
    /// re-read this whenever the project list is fetched.
    func suggestedEntities() async throws -> [ProjectEntity] {
        await Self.projects().map(ProjectEntity.init(project:))
    }

    /// The live list if the app has loaded it, else the offline cache: a cold
    /// background launch from Siri has fetched nothing yet.
    @MainActor
    static func projects() -> [Project] {
        guard let state = AppState.shared else { return [] }
        if state.projects.isEmpty {
            state.hydrateFromCache()
        }
        return state.projects.filter { $0.isArchived != true }
    }
}
