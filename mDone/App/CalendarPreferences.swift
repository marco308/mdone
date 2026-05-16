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

    var id: Int { rawValue }

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
