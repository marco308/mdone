import Foundation

/// A Focus Run: focus on one task, and when it is finished the next task in
/// the list takes its place, until the list runs out or the user ends it.
///
/// The queue is a snapshot of the list's order when the run started, taken
/// from the chosen task down. A snapshot keeps the order predictable while
/// tasks move between the Inbox's date sections under the user's feet. Tasks
/// that stop being eligible along the way (completed elsewhere, deleted) are
/// skipped when their turn comes, so the snapshot never focuses a dead task.
///
/// Pure value type with no ActivityKit or SwiftData, so it is unit-testable
/// and compiles on both platforms.
struct FocusRun: Codable, Equatable {
    /// Task ids still to come, in list order. The focused task is not in here.
    private(set) var queue: [Int64]
    /// Tasks finished during this run, for the summary at the end.
    private(set) var completedCount: Int = 0
    /// Tasks passed over with Skip.
    private(set) var skippedCount: Int = 0

    /// Starts a run at `taskId`, queueing every task listed after it.
    /// Returns nil when the task is not in `order`, since there is then no
    /// "next" to speak of. Duplicate ids (a task can appear in two sections)
    /// keep their first position only.
    init?(startingAt taskId: Int64, in order: [Int64]) {
        guard let index = order.firstIndex(of: taskId) else { return nil }
        var seen: Set<Int64> = [taskId]
        queue = order[(index + 1)...].filter { seen.insert($0).inserted }
    }

    /// Whether `taskId` has anything after it in `order`: the condition for
    /// offering a Focus Run on it at all.
    static func canStart(at taskId: Int64, in order: [Int64]) -> Bool {
        guard let run = FocusRun(startingAt: taskId, in: order) else { return false }
        return !run.queue.isEmpty
    }

    /// The next task still worth focusing, without consuming it.
    func peekNext(where isEligible: (Int64) -> Bool) -> Int64? {
        queue.first(where: isEligible)
    }

    /// How many queued tasks are still eligible, for "3 left" in the UI.
    func remainingCount(where isEligible: (Int64) -> Bool) -> Int {
        queue.filter(isEligible).count
    }

    /// Moves the run on from the focused task, counting it as completed or
    /// skipped, and returns the next eligible task id. Ineligible ids ahead of
    /// it are dropped. Returns nil when the run is over.
    mutating func advance(completedCurrent: Bool, where isEligible: (Int64) -> Bool) -> Int64? {
        if completedCurrent {
            completedCount += 1
        } else {
            skippedCount += 1
        }
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            if isEligible(candidate) {
                return candidate
            }
        }
        return nil
    }
}

/// What a finished run achieved, shown once in place of the focus screen.
struct FocusRunSummary: Equatable {
    let completedCount: Int
    let skippedCount: Int
}
