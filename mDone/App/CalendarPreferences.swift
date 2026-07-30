import Foundation

/// Stored values for the "Start week on" setting. Raw values match
/// `Calendar.firstWeekday` (1 = Sunday … 7 = Saturday); `system` uses 0 so
/// the unset `UserDefaults` default naturally falls back to the device locale.
enum WeekStartPreference: Int, CaseIterable, Identifiable {
    case system = 0
    case sunday = 1
    case monday = 2
    case saturday = 7

    static let storageKey = "firstWeekday"

    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .saturday: "Saturday"
        }
    }
}

extension Calendar {
    /// A calendar that respects the user's "Start week on" preference, falling
    /// back to the device locale when set to "System".
    static var app: Calendar {
        var calendar = Calendar.current
        let stored = UserDefaults.standard.integer(forKey: WeekStartPreference.storageKey)
        if (1 ... 7).contains(stored) {
            calendar.firstWeekday = stored
        }
        return calendar
    }
}

/// Persists whether all-day calendar events appear in mDone.
///
/// We store the *hide* flag rather than a "show" flag so the natural `false`
/// default for a missing key means all-day events keep showing, matching
/// behaviour from before this setting existed.
struct AllDayEventPreference {
    static let storageKey = "hideAllDayEvents"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hidesAllDayEvents: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    /// Pure filter: strips all-day events when the user has hidden them.
    func visibleEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        guard hidesAllDayEvents else { return events }
        return events.filter { !$0.isAllDay }
    }
}
