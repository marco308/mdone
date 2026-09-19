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

    /// The project id the user picked, or nil for automatic. A stored id that
    /// is not a real project (a saved filter picked by an older build, or a
    /// corrupted value) reads as automatic.
    static func storedProjectId(defaults: UserDefaults = .standard) -> Int64? {
        let stored = defaults.integer(forKey: storageKey)
        return stored > 0 ? Int64(stored) : nil
    }

    /// The projects a task can actually be created in. Vikunja hands back its
    /// saved filters and pseudo-projects ("My Open Tasks") alongside the real
    /// ones with negative ids, and `PUT /projects/-2/tasks` is not a thing, so
    /// they can never be the default.
    static func selectable(from projects: [Project]) -> [Project] {
        projects.filter { $0.id > 0 }
    }

    /// The project to add a task to. The user's pick wins while it is still
    /// among `projects`; a deleted or archived pick falls back to automatic,
    /// which prefers a project titled "Inbox" and then the first project.
    static func resolve(in projects: [Project], defaults: UserDefaults = .standard) -> Project? {
        let candidates = selectable(from: projects)
        if let id = storedProjectId(defaults: defaults),
           let picked = candidates.first(where: { $0.id == id })
        {
            return picked
        }
        return candidates.first(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(inboxTitle) == .orderedSame
        }) ?? candidates.first
    }
}
