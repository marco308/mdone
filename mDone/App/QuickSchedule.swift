import Foundation

/// Quick "reschedule to" presets surfaced in the task long-press menu (issue #67).
///
/// Each option resolves to an *absolute* date that ignores the task's current due
/// date, set to the start of the target day (date-only, no specific time). This is
/// distinct from the `+24h` swipe action, which shifts relative to the existing date.
enum QuickSchedule: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case laterThisWeek
    case nextWeek
    case nextMonth

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .laterThisWeek: "Later This Week"
        case .nextWeek: "Next Week"
        case .nextMonth: "Next Month"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .laterThisWeek: "calendar.badge.clock"
        case .nextWeek: "calendar"
        case .nextMonth: "calendar.badge.plus"
        }
    }

    /// Resolves the option to a concrete due date at the start of the target day.
    ///
    /// `now`/`calendar` are injectable for testing; production callers use the app
    /// calendar, which honours the user's "Start week on" preference (issue #60).
    func resolvedDate(now: Date = Date(), calendar: Calendar = .app) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return startOfToday
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case .laterThisWeek:
            // `weekOfYear` interval ends at the start of next week; step back one
            // day for the last day of the current week.
            guard let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: weekEnd)
        case .nextWeek:
            // Start of next week, honouring the user's first-weekday preference.
            return calendar.dateInterval(of: .weekOfYear, for: now)?.end
        case .nextMonth:
            // First day of the following month.
            return calendar.dateInterval(of: .month, for: now)?.end
        }
    }

    /// The options worth showing in the menu for the given moment.
    ///
    /// "Later This Week" is dropped when it would resolve to tomorrow or earlier
    /// (e.g. near the weekend), since it would just duplicate "Today"/"Tomorrow".
    static func options(now: Date = Date(), calendar: Calendar = .app) -> [QuickSchedule] {
        let tomorrow = QuickSchedule.tomorrow.resolvedDate(now: now, calendar: calendar)
        return allCases.filter { option in
            guard option == .laterThisWeek else { return true }
            guard let later = option.resolvedDate(now: now, calendar: calendar), let tomorrow else { return true }
            return later > tomorrow
        }
    }
}
