import Foundation

/// When a task added through Siri or Shortcuts falls due if the caller gave
/// no date. The time of day comes from `DefaultDueTimePreference`, so the
/// "Default due time" setting governs Siri too: with both at their defaults a
/// task said aloud in the car is due today at 6:00 PM.
enum SiriDueDatePreference: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case none

    static let storageKey = "siriDueDate"
    static let defaultValue: SiriDueDatePreference = .today

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .none: String(localized: "No due date")
        }
    }

    /// The stored choice, or `today` when nothing has been set or the stored
    /// value is one this version does not know.
    static func current(defaults: UserDefaults = .standard) -> SiriDueDatePreference {
        defaults.string(forKey: storageKey).flatMap(SiriDueDatePreference.init(rawValue:)) ?? defaultValue
    }

    /// The due date to stamp on a task added right now, or nil for none.
    static func dueDate(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Date? {
        let day: Date
        switch current(defaults: defaults) {
        case .today:
            day = now
        case .tomorrow:
            day = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case .none:
            return nil
        }
        return DefaultDueTimePreference.apply(to: day, calendar: calendar, defaults: defaults)
    }
}
