import Foundation

/// The kinds of relations Vikunja supports between two tasks.
/// Raw values match the API's `relation_kind` strings exactly (all lowercase,
/// no underscores — so they survive the snake-case key decoding untouched).
enum RelationKind: String, Codable, CaseIterable, Identifiable {
    case unknown
    case subtask
    case parenttask
    case related
    case duplicateof
    case duplicates
    case blocking
    case blocked
    case precedes
    case follows
    case copiedfrom
    case copiedto

    var id: String {
        rawValue
    }

    /// Human-readable name, matching the wording of the Vikunja web frontend.
    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .subtask: "Subtask"
        case .parenttask: "Parent Task"
        case .related: "Related"
        case .duplicateof: "Duplicate Of"
        case .duplicates: "Duplicates"
        case .blocking: "Blocking"
        case .blocked: "Blocked By"
        case .precedes: "Precedes"
        case .follows: "Follows"
        case .copiedfrom: "Copied From"
        case .copiedto: "Copied To"
        }
    }

    /// Display name for a raw kind string, falling back to the raw value for
    /// kinds a future server version might add.
    static func label(forRawKind raw: String) -> String {
        RelationKind(rawValue: raw)?.label ?? raw.capitalized
    }
}

/// A single task relation as returned by `PUT /api/v1/tasks/{id}/relations`.
struct TaskRelation: Codable, Hashable {
    var taskId: Int64
    var otherTaskId: Int64
    var relationKind: String
    var created: Date?
}

/// Request body for creating a relation. `relation_kind` encodes as the enum's
/// raw string; key snake-casing is applied by `APIClient`'s encoder.
struct TaskRelationRequest: Encodable {
    var otherTaskId: Int64
    var relationKind: RelationKind
}

/// A task list entry with its nesting depth (0 = top level, 1+ = subtask of
/// the row above it at a lower depth).
struct TaskListRow: Identifiable, Hashable {
    let task: VTask
    let depth: Int

    var id: Int64 {
        task.id
    }
}

/// Orders a task list depth-first so each task's subtasks appear directly
/// beneath it, indented. Pure and view-independent so it can be unit-tested.
enum TaskNesting {
    /// Returns `tasks` reordered for nested display. A task nests under a
    /// parent only when that parent is itself in `tasks`; otherwise it stays
    /// at the top level, so no task ever disappears from a filtered list
    /// (e.g. a subtask due today whose parent is due next week).
    ///
    /// Every input task is emitted exactly once: an `emitted` guard makes the
    /// walk safe against relation cycles and tasks with multiple parents
    /// (both representable in Vikunja), and a final sweep catches tasks whose
    /// parents form a cycle among themselves.
    static func rows(for tasks: [VTask]) -> [TaskListRow] {
        let presentIds = Set(tasks.map(\.id))

        var childrenByParent: [Int64: [VTask]] = [:]
        var childIds = Set<Int64>()
        for task in tasks {
            for parent in task.parentTasks where parent.id != task.id && presentIds.contains(parent.id) {
                childrenByParent[parent.id, default: []].append(task)
                childIds.insert(task.id)
            }
        }

        // Fast path: nothing to nest, keep the caller's ordering untouched.
        guard !childIds.isEmpty else {
            return tasks.map { TaskListRow(task: $0, depth: 0) }
        }

        var result: [TaskListRow] = []
        var emitted = Set<Int64>()

        func emit(_ task: VTask, depth: Int) {
            guard emitted.insert(task.id).inserted else { return }
            result.append(TaskListRow(task: task, depth: depth))
            for child in childrenByParent[task.id] ?? [] {
                emit(child, depth: depth + 1)
            }
        }

        for task in tasks where !childIds.contains(task.id) {
            emit(task, depth: 0)
        }
        // Tasks unreachable from any top-level task (their parents form a
        // cycle) still need to show up — surface them flat.
        for task in tasks {
            emit(task, depth: 0)
        }
        return result
    }
}
