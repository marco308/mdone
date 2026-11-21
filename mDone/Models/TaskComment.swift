import Foundation

/// A comment on a task (#2). `comment` is HTML, as Vikunja's web editor
/// writes it; mDone writes the same with `DescriptionMarkup`.
struct TaskComment: Codable, Identifiable, Hashable {
    let id: Int64
    var comment: String
    var author: User?
    var created: Date?
    var updated: Date?

    /// Whether the comment was changed after it was posted. The server sets
    /// both dates on create, a few microseconds apart, so anything under a
    /// second is the same moment.
    var isEdited: Bool {
        guard let created, let updated else { return false }
        return updated.timeIntervalSince(created) >= 1
    }
}

struct TaskCommentRequest: Encodable {
    var comment: String
}
