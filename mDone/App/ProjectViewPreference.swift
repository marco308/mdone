import Foundation

/// The two ways a project's tasks can be shown. Boards exist on iOS only, and
/// only for projects the server gives a Kanban view, so `board` falls back to
/// the list wherever a board cannot be drawn.
enum ProjectViewMode: String, CaseIterable, Identifiable {
    case list
    case board

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .list: String(localized: "List")
        case .board: String(localized: "Board")
        }
    }
}

/// Which view each project opens in.
///
/// Two levels, the same shape as `TaskSortPreference`: a per-project choice,
/// written whenever the board toggle in a project's toolbar is tapped, and a
/// default from Settings for every project that has no choice of its own.
/// Issue #184: the board used to reset to the list on every open, so anyone
/// who works on a board had to switch again each time they opened a project.
enum ProjectViewPreference {
    static let defaultStorageKey = "projectView.default"

    /// The list, which is what every project showed before this setting
    /// existed, so nobody's projects open differently on upgrade.
    static let fallback = ProjectViewMode.list

    static func projectStorageKey(for projectId: Int64) -> String {
        "projectView.project.\(projectId)"
    }

    /// The view projects open in when they have no remembered choice.
    static func defaultMode(defaults: UserDefaults = .standard) -> ProjectViewMode {
        mode(forKey: defaultStorageKey, defaults: defaults) ?? fallback
    }

    /// The view `projectId` should open in: its own remembered choice, else
    /// the default from Settings.
    static func mode(for projectId: Int64, defaults: UserDefaults = .standard) -> ProjectViewMode {
        mode(forKey: projectStorageKey(for: projectId), defaults: defaults) ?? defaultMode(defaults: defaults)
    }

    /// Remembers `mode` for `projectId`. Written on every toggle, so a project
    /// switched back to the list stays on the list even when the default is
    /// the board.
    static func save(_ mode: ProjectViewMode, for projectId: Int64, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: projectStorageKey(for: projectId))
    }

    /// Drops `projectId`'s remembered choice, putting it back on the default.
    static func clear(for projectId: Int64, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: projectStorageKey(for: projectId))
    }

    /// `nil` for a missing key and for anything that isn't a mode we wrote,
    /// so a stored value from a future version falls back rather than crashing.
    private static func mode(forKey key: String, defaults: UserDefaults) -> ProjectViewMode? {
        guard let stored = defaults.string(forKey: key) else { return nil }
        return ProjectViewMode(rawValue: stored)
    }
}
