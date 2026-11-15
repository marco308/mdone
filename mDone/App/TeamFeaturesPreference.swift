import Foundation

/// The "Team features" setting (#272). Off by default, so someone who only
/// uses mDone for their own tasks never sees assignees, the assignee picker
/// or the "Assigned to me" filter, and the app makes no extra requests for
/// them. Turning it on is for projects shared with other people in Vikunja.
///
/// Assignees set elsewhere are kept either way: task updates are a `PATCH`
/// that leaves assignees out unless the user changed them (#292).
enum TeamFeaturesPreference {
    static let storageKey = "teamFeaturesEnabled"
    static let defaultValue = false

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}
