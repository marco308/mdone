import Foundation

/// User preference for the time-of-day applied to tasks created with a
/// date but no explicit time, plus helpers to merge the preference into a
/// `Date`.
enum DueDateDefaults {
    /// `@AppStorage` key. Stored as minutes-since-midnight so the value
    /// survives `UserDefaults`' `Int` storage without losing precision.
    static let storageKey = "defaultDueTimeMinutes"

    /// Vikunja's web UI uses 18:00; we mirror that so users coming from
    /// the web see consistent behaviour.
    static let defaultMinutes = 18 * 60

    /// Returns a copy of `date` with the hour/minute taken from
    /// `minutes-since-midnight`, only when `date` is at exactly 00:00.
    /// Dates that already carry a specific time pass through unchanged.
    static func apply(
        defaultMinutes minutes: Int,
        to date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard (components.hour ?? 0) == 0, (components.minute ?? 0) == 0 else { return date }
        let clamped = max(0, min(minutes, 24 * 60 - 1))
        let hour = clamped / 60
        let minute = clamped % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// Convenience: read the preference from `UserDefaults` and apply.
    static func apply(to date: Date, calendar: Calendar = .current) -> Date {
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Int
        return apply(defaultMinutes: stored ?? defaultMinutes, to: date, calendar: calendar)
    }
}
