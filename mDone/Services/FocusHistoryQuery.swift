import Foundation
import SwiftData

/// Read-only queries over `FocusRecord`. Cross-platform — iOS captures the data,
/// both iOS and macOS surface it on task detail screens.
enum FocusHistoryQuery {
    /// Total focused seconds across every recorded session for a task.
    @MainActor
    static func totalFocus(for taskId: Int64, in context: ModelContext) -> TimeInterval {
        let predicate = #Predicate<FocusRecord> { $0.taskId == taskId }
        let descriptor = FetchDescriptor<FocusRecord>(predicate: predicate)
        guard let records = try? context.fetch(descriptor) else { return 0 }
        return records.reduce(0) { $0 + $1.focusedSeconds }
    }

    /// Number of recorded sessions for a task.
    @MainActor
    static func sessionCount(for taskId: Int64, in context: ModelContext) -> Int {
        let predicate = #Predicate<FocusRecord> { $0.taskId == taskId }
        var descriptor = FetchDescriptor<FocusRecord>(predicate: predicate)
        descriptor.propertiesToFetch = [\.taskId]
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Most this many recent `FocusRecord` rows feed the suggester. Caps
    /// the typing-path fetch so a pathological focus history can't tank
    /// the UI; in practice an active user accrues a few rows per task per
    /// day, so 500 rows covers a long working memory without truncating
    /// the realistic "tasks I might do again" set.
    static let historicalTasksFetchLimit = 500

    /// Every task that has recorded focus time, collapsed to one
    /// `HistoricalTask` per task id with its title and *total* focused
    /// seconds across the inspected window. This is the input the offline
    /// `EstimateSuggester` matches a new title against — only tasks the
    /// user actually spent focused time on are eligible, which is our proxy
    /// for "completed work with a known duration". `FocusRecord` carries
    /// `projectName` (display string) but no project/label ids, so those
    /// weak signals are left unset here; the suggester degrades gracefully
    /// to title-only matching.
    ///
    /// Runs on the typing-path debounce so it: (a) only fetches the columns
    /// the suggester actually consumes, (b) caps the row count at
    /// `historicalTasksFetchLimit` so worst-case fetch is bounded, and
    /// (c) sorts records newest-first and keeps the first-seen title per
    /// taskId (so the kept title is deterministically the most recent).
    @MainActor
    static func historicalTasks(in context: ModelContext) -> [HistoricalTask] {
        var descriptor = FetchDescriptor<FocusRecord>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.taskId, \.taskTitle, \.focusedSeconds, \.endedAt]
        descriptor.fetchLimit = historicalTasksFetchLimit
        guard let records = try? context.fetch(descriptor) else { return [] }
        var byTask: [Int64: (title: String, seconds: TimeInterval)] = [:]
        for r in records {
            if var existing = byTask[r.taskId] {
                existing.seconds += r.focusedSeconds
                // Title is set from the first sighting (newest record)
                // because we iterate newest-first; older rows only
                // contribute their seconds, not a stale title.
                byTask[r.taskId] = existing
            } else {
                byTask[r.taskId] = (r.taskTitle, r.focusedSeconds)
            }
        }
        return byTask.values
            .filter { $0.seconds > 0 && !$0.title.isEmpty }
            .map { HistoricalTask(title: $0.title, actualSeconds: $0.seconds) }
    }
}
