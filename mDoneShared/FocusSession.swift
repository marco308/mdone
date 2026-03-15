import Foundation

struct FocusSession: Codable, Equatable {
    let taskId: Int64
    let taskTitle: String
    let projectName: String
    let priorityLevel: Int
    let sessionStartDate: Date
    var focusIntervalStartDate: Date
    var elapsedBeforePause: TimeInterval
    var isPaused: Bool
    var activityId: String?

    func totalElapsed(at date: Date = Date()) -> TimeInterval {
        if isPaused {
            return elapsedBeforePause
        }
        return elapsedBeforePause + date.timeIntervalSince(focusIntervalStartDate)
    }

    /// Synthetic start date for Text(timerInterval:) that accounts for prior intervals
    var syntheticStartDate: Date {
        Date(timeIntervalSince1970: focusIntervalStartDate.timeIntervalSince1970 - elapsedBeforePause)
    }
}
