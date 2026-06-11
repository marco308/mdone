import Foundation

/// Quick-reschedule presets surfaced in a task's long-press menu.
///
/// Unlike the "+24h" swipe action (which shifts relative to the task's current
/// due date), each option produces an *absolute* due date computed from today,
/// ignoring whatever date the task currently has. Results are normalised to the
/// start of the target day, so the rescheduled task becomes date-only (no
/// specific time), matching how `VTask.hasSpecificTime` treats midnight.
enum ScheduleOption: CaseIterable, Identifiable {
    case today
    case tomorrow
    case thisWeekend
    case nextWeek
    case nextMonth

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeekend: "This Weekend"
        case .nextWeek: "Next Week"
        case .nextMonth: "Next Month"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .thisWeekend: "calendar.day.timeline.left"
        case .nextWeek: "calendar"
        case .nextMonth: "calendar.badge.clock"
        }
    }

    /// The absolute due date for this option, computed from `now` using a
    /// calendar that honours the user's "Start week on" preference (issue #60).
    func date(from now: Date = Date(), calendar: Calendar = .app) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let target: Date = switch self {
        case .today:
            startOfToday
        case .tomorrow:
            calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        case .thisWeekend:
            // Upcoming Saturday. If today is already Saturday, rolls to next Saturday.
            calendar.nextDate(
                after: now,
                matching: DateComponents(weekday: 7),
                matchingPolicy: .nextTime
            ) ?? startOfToday
        case .nextWeek:
            // Start of next week, respecting the user's first-weekday preference.
            if let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start {
                calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart) ?? startOfToday
            } else {
                calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
            }
        case .nextMonth:
            // First day of the following month.
            if let monthStart = calendar.dateInterval(of: .month, for: now)?.start {
                calendar.date(byAdding: .month, value: 1, to: monthStart) ?? startOfToday
            } else {
                calendar.date(byAdding: .month, value: 1, to: startOfToday) ?? startOfToday
            }
        }
        return calendar.startOfDay(for: target)
    }
}
