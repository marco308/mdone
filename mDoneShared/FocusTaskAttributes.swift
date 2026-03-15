#if os(iOS)
import ActivityKit
import Foundation

struct FocusTaskAttributes: ActivityAttributes {
    // Static data — set once when starting the Live Activity
    let taskId: Int64
    let taskTitle: String
    let projectName: String
    let priorityLevel: Int

    // Dynamic data — updated via activity.update()
    struct ContentState: Codable, Hashable {
        /// When active: synthetic date = Date() - elapsedBeforePause, so timer shows total elapsed.
        /// When paused: the date when the current interval started (before pausing).
        let focusStartDate: Date
        let isPaused: Bool
        /// Accumulated time from prior focus intervals (before current one).
        let elapsedBeforePause: TimeInterval
    }
}
#endif
