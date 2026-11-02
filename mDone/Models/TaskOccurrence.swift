import Foundation

/// One appearance of a task on one day.
///
/// An appearance is either real, meaning the task's own dates put it there, or
/// projected, meaning the app worked out from the task's recurrence that it will
/// come back on that day. Vikunja stores only the current instance of a
/// repeating task, so a projected occurrence has no row of its own on the
/// server: it carries the **real** task, and only its placement is invented.
///
/// That is deliberate. Synthesizing a stand-in `VTask` would put a row in the
/// app that mutation paths could resolve by id, and those paths reach the
/// SwiftData cache, the offline operation queue, the widget's shared data and
/// notification identifiers. Carrying the real task means a projection cannot
/// name something that does not exist. It must still never be completed,
/// edited, rescheduled or deleted, which the views enforce by routing it
/// through `TaskRow`'s existing read-only path.
struct TaskOccurrence: Identifiable, Hashable {
    /// The real task, exactly as the server sent it.
    let task: VTask

    /// Start of the day this appearance belongs to. Also half the identity,
    /// which is what makes "one row per task per day" structural rather than a
    /// convention every future caller has to remember: a `ForEach` cannot end
    /// up with two rows sharing an id, even for a task repeating hourly.
    let day: Date

    /// Non-nil exactly when this appearance was projected, holding the
    /// projected due date with its time of day, which is what the row shows
    /// instead of the task's stored due date. One field rather than a flag and
    /// a date, so the two cannot disagree.
    let projectedDueDate: Date?

    var isProjected: Bool { projectedDueDate != nil }

    struct ID: Hashable {
        let taskId: Int64
        let day: Date
    }

    var id: ID { ID(taskId: task.id, day: day) }
}
