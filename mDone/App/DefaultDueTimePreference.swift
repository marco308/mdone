import Foundation

/// Stored values for the "Default due time" setting. The raw value encodes the
/// time of day as `hour * 100 + minute`, so 0 is midnight, 1800 is 18:00, and
/// `endOfDay` (2359) is one minute before midnight. An unset preference reads
/// back as 0 (`UserDefaults.integer(forKey:)`), which would land tasks at
/// midnight — exactly the bug we're fixing — so an explicit `.unset` sentinel
/// triggers the `defaultRawValue` fallback when no choice has been made yet.
enum DefaultDueTimePreference: Int, CaseIterable, Identifiable {
    case unset = -1
    case nineAM = 900
    case noon = 1200
    case fivePM = 1700
    case sixPM = 1800
    case ninePM = 2100
    case endOfDay = 2359

    static let storageKey = "defaultDueTime"

    /// Matches Vikunja's web frontend, which defaults same-day tasks to 18:00.
    static let defaultRawValue: Int = sixPM.rawValue

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unset: "Default"
        case .nineAM: "9:00 AM"
        case .noon: "12:00 PM"
        case .fivePM: "5:00 PM"
        case .sixPM: "6:00 PM"
        case .ninePM: "9:00 PM"
        case .endOfDay: "End of day"
        }
    }

    var hour: Int { rawValue / 100 }
    var minute: Int { rawValue % 100 }

    /// Reads the user's stored preference, falling back to `defaultRawValue`
    /// when nothing has been set or the stored value is unrecognised.
    static func current(defaults: UserDefaults = .standard) -> DefaultDueTimePreference {
        let stored = defaults.object(forKey: storageKey) as? Int ?? defaultRawValue
        return DefaultDueTimePreference(rawValue: stored) ?? sixPM
    }

    /// Returns `date` with its time component replaced by the user's chosen
    /// default time. Used when the UI needs to seed a due date that does not
    /// otherwise carry an explicit time-of-day (e.g. the inbox quick add).
    static func apply(
        to date: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Date {
        let preference = current(defaults: defaults)
        return calendar.date(
            bySettingHour: preference.hour,
            minute: preference.minute,
            second: 0,
            of: date
        ) ?? date
    }
}
