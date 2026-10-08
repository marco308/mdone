import Foundation

/// A Kanban column. In Vikunja, buckets belong to a project's *kanban* view and
/// carry the tasks placed in that column. The view-tasks endpoint
/// (`/views/{view}/tasks`) returns these buckets with their tasks embedded
/// (`tasks`), so a single fetch is enough to render a board. `tasks` is omitted
/// entirely for empty buckets (Vikunja marshals it with `omitempty`).
///
/// Equality is the synthesised, whole-value kind on purpose. The board holds
/// its buckets in `@State`, and SwiftUI skips the update when a new value
/// compares equal to the old one: with id-only equality, reordering the
/// cards in a column left the screen showing the old order.
struct Bucket: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var projectViewId: Int64?
    var tasks: [VTask]?
    /// Work-in-progress limit. `0` (or `nil`) means unlimited.
    var limit: Int64?
    /// Server-reported task count for the bucket. May be absent.
    var count: Int64?
    var position: Double?

    /// Every task in this bucket, in its stored order, done ones included. Unlike
    /// the list views, a board keeps finished work on show: a task's column is
    /// what says it is finished, and hiding done tasks left a "Done" column
    /// looking empty while the Vikunja web app showed its cards (#238).
    var allTasks: [VTask] {
        tasks ?? []
    }

    /// Whether the bucket has a meaningful WIP limit set.
    var hasLimit: Bool {
        (limit ?? 0) > 0
    }

    /// `true` when a WIP limit is set and the task count meets or exceeds it.
    /// Done tasks count, as they do when Vikunja enforces the limit.
    var isOverLimit: Bool {
        guard let limit, limit > 0 else { return false }
        return Int64(allTasks.count) >= limit
    }
}

/// Request body for moving a task into a bucket
/// (`POST /api/v1/projects/{project}/views/{view}/buckets/{bucket}/tasks`).
/// The bucket and view come from the URL path; only `taskId` is sent.
struct TaskBucketRequest: Encodable {
    var taskId: Int64
}
