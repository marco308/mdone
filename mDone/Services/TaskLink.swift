import Foundation

/// The web link for a task on the user's Vikunja server, for sharing a task
/// with someone or something that can open it: a person in the web app, or an
/// agent with Vikunja access that reads the ID back out of the URL.
///
/// Vikunja's web app serves a task at `/tasks/{id}` under the same base URL the
/// API lives on, so the link is built from the stored server URL rather than
/// anything the API returns.
enum TaskLink {
    /// The link for `taskId` on `serverURL`, or nil when the server URL is
    /// missing or cannot be made sense of.
    static func url(forTaskId taskId: Int64, serverURL: String?) -> URL? {
        guard let serverURL, let base = ServerURL.normalized(serverURL) else { return nil }
        return base.appendingPathComponent("tasks").appendingPathComponent(String(taskId))
    }

    /// The link for `task` on the server the user is signed in to.
    static func url(for task: VTask) -> URL? {
        url(forTaskId: task.id, serverURL: AuthService.shared.getServerURL())
    }
}
