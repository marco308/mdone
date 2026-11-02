import Foundation

/// Works out the `position` to send when a task is dragged somewhere new.
///
/// Vikunja stores one float position per task per view and sorts ascending,
/// so a move is "pick a number between the new neighbours". The rules here are
/// the ones Vikunja's own web app uses (`calculateItemPosition.ts`), so mDone
/// and the web app produce the same numbers for the same drag:
///
/// - between two neighbours: the midpoint
/// - dropped at the top: half the first task's position
/// - dropped at the bottom: the last task's position plus 2^16
/// - neighbours that share a position: just above the lower one
/// - into an empty list: 0
///
/// A task with no position row reports `0` from the server; `0` and any
/// value under 0.01 make Vikunja (v1.0+) recalculate the whole view and
/// answer with a repaired number, so callers refetch after a move rather
/// than trusting what they sent. Pure and DB-free so it stays unit-testable.
enum TaskPositioning {
    /// Gap left after the last task, so many appends fit before neighbours
    /// need repairing. Vikunja's `2^16`.
    static let endGap: Double = 65536

    /// Vikunja's `MIN_POSITION_SPACING`: the nudge used when two neighbours
    /// already share a position.
    static let minimumSpacing: Double = 0.01

    /// The position for a task landing between `before` and `after`, either
    /// of which is `nil` when the task landed at that end of the list.
    static func position(between before: Double?, and after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil):
            return 0
        case let (nil, after?):
            return after / 2
        case let (before?, nil):
            return before + endGap
        case let (before?, after?):
            if before == after {
                return after + minimumSpacing
            }
            return before + (after - before) / 2
        }
    }

    /// The outcome of a list drag: which task moved, the position to send for
    /// it, and the list in its new order for the UI to show straight away.
    struct Move: Equatable {
        var task: VTask
        var position: Double
        var reordered: [VTask]
    }

    /// Applies a SwiftUI `onMove` (`source` offsets, `destination` in the
    /// pre-move indexing) to `tasks`, which must be in the order on screen.
    /// Returns `nil` for a drop that changes nothing, and for a multi-row
    /// selection: the position endpoint moves one task at a time.
    static func move(_ tasks: [VTask], fromOffsets source: IndexSet, toOffset destination: Int) -> Move? {
        guard source.count == 1, let from = source.first, tasks.indices.contains(from) else { return nil }
        var reordered = tasks
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered != tasks else { return nil }

        let landed = from < destination ? destination - 1 : destination
        return Move(
            task: tasks[from],
            position: position(forIndex: landed, in: reordered),
            reordered: reordered
        )
    }

    /// The position for `task` placed at `index` in `tasks`, a list that does
    /// not yet contain it (a board column, say). `index` past the end appends.
    static func position(forInserting task: VTask, at index: Int, into tasks: [VTask]) -> Double {
        let others = tasks.filter { $0.id != task.id }
        let clamped = min(max(index, 0), others.count)
        var placed = others
        placed.insert(task, at: clamped)
        return position(forIndex: clamped, in: placed)
    }

    /// The position for the task at `index` of `ordered`, read from its
    /// neighbours. A neighbour with no position (never fetched through a
    /// view) counts as `0`, the value the server reports for it.
    private static func position(forIndex index: Int, in ordered: [VTask]) -> Double {
        let before = index > 0 ? (ordered[index - 1].position ?? 0) : nil
        let after = index < ordered.count - 1 ? (ordered[index + 1].position ?? 0) : nil
        return position(between: before, and: after)
    }
}
