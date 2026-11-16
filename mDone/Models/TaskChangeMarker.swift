import Foundation

/// A cheap fingerprint of the server's task list, read before live refresh
/// downloads the whole list (#241). Creating or deleting a task changes
/// `total`; editing, completing or labelling one stamps it with a new
/// `updated` time, which makes it the latest (checked against Vikunja 2.4).
/// When neither moves, the list has not changed in any way that stamps a
/// task.
///
/// Not everything does: a drag in another client changes a position, not
/// the task, and a saved filter's matches can drift with the clock alone.
/// Live refresh still reads the full list every few minutes and on returning
/// to the app to catch those.
struct TaskChangeMarker: Equatable, Sendable {
    var total: Int?
    var latestUpdated: Date?
    var latestId: Int64?

    /// Builds the marker from a probe page. The server sorts by `updated`, so
    /// the page holds the latest task; the maximum is taken anyway so a
    /// server that ignores the sort still gives a stable answer.
    init(total: Int?, tasks: [VTask]) {
        self.total = total
        let latest = tasks.max { lhs, rhs in
            (lhs.updated ?? .distantPast, lhs.id) < (rhs.updated ?? .distantPast, rhs.id)
        }
        latestUpdated = latest?.updated
        latestId = latest?.id
    }
}
