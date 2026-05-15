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
}
