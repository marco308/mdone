import Foundation

/// A task edit made while offline, stored as the user's **intent** (only the
/// fields they actually changed) rather than a ready-to-send request body.
///
/// Storing intent is what makes replay safe. Vikunja's task update is a full
/// replace, so a body built offline and replayed an hour later would overwrite
/// every field with the values the task had when the device went offline,
/// destroying anything changed elsewhere in the meantime. On replay the intent
/// is merged onto a freshly-read copy of the task instead (issue #146).
///
/// Labels are deliberately absent: they're managed through their own endpoints,
/// not the task update, so marking a task Current offline isn't queueable here.
struct QueuedTaskEdit: Codable, Equatable {
    var done: Bool?
    var title: String?
    var taskDescription: String?
    var priority: Int64?
    var percentDone: Double?
    var projectId: Int64?
    var dueDate: Date?
    var startDate: Date?
    var endDate: Date?
    var repeatAfter: Int64?
    var repeatMode: Int64?
    var reminders: [TaskReminder]?
    /// Captured for completeness: the app doesn't set these itself today, so an
    /// offline edit leaves them nil and the replay merge fills them from the
    /// fresh server copy. Recorded anyway so a future editor of colour or
    /// favourite status doesn't silently lose it offline.
    var hexColor: String?
    var isFavorite: Bool?
    var clearDueDate: Bool?
    var clearStartDate: Bool?
    var clearEndDate: Bool?

    /// Captures a request the app was about to send. Only the fields the caller
    /// set are recorded; everything nil stays nil so replay knows not to touch it.
    init(from request: TaskUpdateRequest) {
        done = request.done
        title = request.title
        taskDescription = request.description
        priority = request.priority
        percentDone = request.percentDone
        projectId = request.projectId
        dueDate = request.dueDate
        startDate = request.startDate
        endDate = request.endDate
        repeatAfter = request.repeatAfter
        repeatMode = request.repeatMode
        reminders = request.reminders
        hexColor = request.hexColor
        isFavorite = request.isFavorite
        clearDueDate = request.clearDueDate
        clearStartDate = request.clearStartDate
        clearEndDate = request.clearEndDate
    }

    /// Rebuilds the request. Still needs `preservingExistingValues(from:)`
    /// applied against a fresh task before it goes on the wire (issue #147).
    var request: TaskUpdateRequest {
        var result = TaskUpdateRequest()
        result.done = done
        result.title = title
        result.description = taskDescription
        result.priority = priority
        result.percentDone = percentDone
        result.projectId = projectId
        result.dueDate = dueDate
        result.startDate = startDate
        result.endDate = endDate
        result.repeatAfter = repeatAfter
        result.repeatMode = repeatMode
        result.reminders = reminders
        result.hexColor = hexColor
        result.isFavorite = isFavorite
        result.clearDueDate = clearDueDate
        result.clearStartDate = clearStartDate
        result.clearEndDate = clearEndDate
        return result
    }

    /// Folds a later edit of the same task into this one, newer values winning
    /// field by field. Without this, ticking a task on and off five times while
    /// offline would replay five requests instead of settling on the final state.
    ///
    /// A clear flag and its date are mutually exclusive, so setting either side
    /// in the newer edit drops the other.
    func coalesced(with newer: QueuedTaskEdit) -> QueuedTaskEdit {
        var result = self
        if let value = newer.done {
            result.done = value
        }
        if let value = newer.title {
            result.title = value
        }
        if let value = newer.taskDescription {
            result.taskDescription = value
        }
        if let value = newer.priority {
            result.priority = value
        }
        if let value = newer.percentDone {
            result.percentDone = value
        }
        if let value = newer.projectId {
            result.projectId = value
        }
        if let value = newer.repeatAfter {
            result.repeatAfter = value
        }
        if let value = newer.repeatMode {
            result.repeatMode = value
        }
        if let value = newer.reminders {
            result.reminders = value
        }
        if let value = newer.hexColor {
            result.hexColor = value
        }
        if let value = newer.isFavorite {
            result.isFavorite = value
        }

        if newer.clearDueDate == true {
            result.clearDueDate = true
            result.dueDate = nil
        } else if let value = newer.dueDate {
            result.dueDate = value
            result.clearDueDate = nil
        }

        if newer.clearStartDate == true {
            result.clearStartDate = true
            result.startDate = nil
        } else if let value = newer.startDate {
            result.startDate = value
            result.clearStartDate = nil
        }

        if newer.clearEndDate == true {
            result.clearEndDate = true
            result.endDate = nil
        } else if let value = newer.endDate {
            result.endDate = value
            result.clearEndDate = nil
        }

        return result
    }

    /// Applies the edit to a local copy so the UI and cache reflect it straight
    /// away, before the server has seen it.
    func applied(to task: VTask) -> VTask {
        var result = task
        if let done {
            result.done = done
        }
        if let title {
            result.title = title
        }
        if let taskDescription {
            result.description = taskDescription
        }
        if let priority {
            result.priority = priority
        }
        if let percentDone {
            result.percentDone = percentDone
        }
        if let projectId {
            result.projectId = projectId
        }
        if let repeatAfter {
            result.repeatAfter = repeatAfter
        }
        if let repeatMode {
            result.repeatMode = repeatMode
        }
        if let reminders {
            result.reminders = reminders
        }
        if let hexColor {
            result.hexColor = hexColor
        }
        if let isFavorite {
            result.isFavorite = isFavorite
        }
        if clearDueDate == true {
            result.dueDate = nil
        } else if let dueDate {
            result.dueDate = dueDate
        }
        if clearStartDate == true {
            result.startDate = nil
        } else if let startDate {
            result.startDate = startDate
        }
        if clearEndDate == true {
            result.endDate = nil
        } else if let endDate {
            result.endDate = endDate
        }
        return result
    }
}
