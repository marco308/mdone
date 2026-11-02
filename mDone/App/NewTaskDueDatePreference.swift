import Foundation

/// When a task falls due if the user gave no date. Two settings share these
/// choices: one for tasks added through Siri or Shortcuts, one for tasks added
/// from the Inbox quick-add bar (#210). The time of day comes from
/// `DefaultDueTimePreference`, so the "Default due time" setting governs both:
/// with everything at its defaults a task said aloud in the car is due today
/// at 6:00 PM.
enum NewTaskDueDatePreference: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case none

    /// Tasks added through Siri or Shortcuts. The key predates the Inbox
    /// setting and keeps its name so existing choices carry over.
    static let siriStorageKey = "siriDueDate"
    /// Tasks added from the Inbox quick-add bar.
    static let inboxStorageKey = "inboxDueDate"
    static let defaultValue: NewTaskDueDatePreference = .today

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

    /// The stored choice under `key`, or `today` when nothing has been set or
    /// the stored value is one this version does not know.
    static func current(forKey key: String, defaults: UserDefaults = .standard) -> NewTaskDueDatePreference {
        defaults.string(forKey: key).flatMap(NewTaskDueDatePreference.init(rawValue:)) ?? defaultValue
    }

    /// The due date to stamp on a task added right now, or nil for none.
    static func dueDate(
        forKey key: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Date? {
        let day: Date
        switch current(forKey: key, defaults: defaults) {
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
