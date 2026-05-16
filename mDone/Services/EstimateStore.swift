import Foundation
import SwiftData

/// CRUD over `TaskEstimate`, the mDone-local optional estimated duration for a
/// task. MainActor-scoped and `ModelContext`-injected exactly like
/// `FocusHistoryQuery` so it can share the app's main container while staying
/// trivially unit-testable against an in-memory container.
///
/// All operations are keyed by Vikunja task id. Absence of a row is a
/// first-class state: `estimate(for:)` returns `nil`, which the UI treats as
/// "no estimate, feature invisible". There is at most one row per task id
/// (enforced by `@Attribute(.unique)` on `TaskEstimate.taskId`).
enum EstimateStore {
    /// The estimated duration in seconds for a task, or `nil` if none was set.
    @MainActor
    static func estimate(for taskId: Int64, in context: ModelContext) -> TimeInterval? {
        record(for: taskId, in: context)?.estimatedSeconds
    }

    /// Set (or replace) the estimate for a task. A non-positive value is
    /// treated as "clear" so callers never persist a meaningless 0.
    @MainActor
    static func set(_ seconds: TimeInterval, for taskId: Int64, in context: ModelContext) {
        guard seconds > 0 else {
            clear(for: taskId, in: context)
            return
        }
        if let existing = record(for: taskId, in: context) {
            existing.estimatedSeconds = seconds
            existing.updatedAt = Date()
        } else {
            context.insert(TaskEstimate(taskId: taskId, estimatedSeconds: seconds))
        }
        try? context.save()
    }

    /// Remove any estimate for a task. No-op if there is none (unknown id).
    @MainActor
    static func clear(for taskId: Int64, in context: ModelContext) {
        guard let existing = record(for: taskId, in: context) else { return }
        context.delete(existing)
        try? context.save()
    }

    @MainActor
    private static func record(for taskId: Int64, in context: ModelContext) -> TaskEstimate? {
        let predicate = #Predicate<TaskEstimate> { $0.taskId == taskId }
        var descriptor = FetchDescriptor<TaskEstimate>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
