import Foundation

/// Where a task goes when the user adds it without naming a project: the
/// Inbox quick-add bar, Siri, and the Mac new-task sheet (#210).
///
/// The setting stores a project id, with `automatic` (0) meaning "let the app
/// pick". Vikunja ids start at 1, so 0 can never collide with a real project.
enum DefaultProjectPreference {
    static let storageKey = "defaultProjectId"
    static let automatic = 0

    /// Vikunja creates a project with this title for every new account, so it
    /// is the natural home for tasks when the user has not picked one.
    static let inboxTitle = "Inbox"

    /// The project id the user picked, or nil for automatic.
    static func storedProjectId(defaults: UserDefaults = .standard) -> Int64? {
        let stored = defaults.integer(forKey: storageKey)
        return stored == automatic ? nil : Int64(stored)
    }

    /// The project to add a task to. The user's pick wins while it is still
    /// among `projects`; a deleted or archived pick falls back to automatic,
    /// which prefers a project titled "Inbox" and then the first project.
    static func resolve(in projects: [Project], defaults: UserDefaults = .standard) -> Project? {
        if let id = storedProjectId(defaults: defaults),
           let picked = projects.first(where: { $0.id == id })
        {
            return picked
        }
        return projects.first(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(inboxTitle) == .orderedSame
        }) ?? projects.first
    }
}
