import Foundation

struct Project: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var description: String?
    var hexColor: String?
    var isArchived: Bool?
    var isFavorite: Bool?
    var position: Double?
    var owner: User?
    var created: Date?
    var updated: Date?
    var parentProjectId: Int64?
    var defaultBucketId: Int64?
    var doneBucketId: Int64?
    var views: [ProjectView]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }

    var listViewId: Int64? {
        views?.first(where: { $0.viewKind == "list" })?.id
    }

    /// The id of this project's Kanban view, if it has one. Vikunja creates a
    /// kanban view for every project by default, so this is normally non-nil
    /// once `views` has been loaded.
    var kanbanViewId: Int64? {
        views?.first(where: { $0.viewKind == "kanban" })?.id
    }
}

struct ProjectView: Codable, Identifiable {
    let id: Int64
    var title: String
    var projectId: Int64
    var viewKind: String?
    var position: Double?
    var bucketConfigurationMode: String?
    var defaultBucketId: Int64?
    var doneBucketId: Int64?
}

/// Request body for creating a project (`PUT /api/v1/projects`).
/// `title` is required by Vikunja (1–250 chars); other fields are optional.
/// Snake-casing (`hexColor` → `hex_color`) is applied by `APIClient`'s encoder.
struct ProjectCreateRequest: Encodable {
    var title: String
    var description: String?
    var hexColor: String?
    var isFavorite: Bool?
}

/// Request body for updating a project (`POST /api/v1/projects/{id}`).
///
/// We always send the project's *full* field set (not a partial patch): Vikunja's
/// update can reset omitted columns and may skip zero-value booleans, so sending
/// every field is what makes archive (`isArchived = true`) and especially
/// unarchive (`isArchived = false`) reliable. Build these from an existing
/// `Project` via the `init(from:)` convenience initializer.
struct ProjectUpdateRequest: Encodable {
    var title: String
    var description: String
    var hexColor: String
    var isFavorite: Bool
    var isArchived: Bool

    init(title: String, description: String, hexColor: String, isFavorite: Bool, isArchived: Bool) {
        self.title = title
        self.description = description
        self.hexColor = hexColor
        self.isFavorite = isFavorite
        self.isArchived = isArchived
    }

    /// Builds a full update request from an existing project, overriding only the
    /// fields you pass. Ensures we never accidentally blank out a field on the server.
    init(
        from project: Project,
        title: String? = nil,
        description: String? = nil,
        hexColor: String? = nil,
        isFavorite: Bool? = nil,
        isArchived: Bool? = nil
    ) {
        self.title = title ?? project.title
        self.description = description ?? project.description ?? ""
        self.hexColor = hexColor ?? project.hexColor ?? ""
        self.isFavorite = isFavorite ?? project.isFavorite ?? false
        self.isArchived = isArchived ?? project.isArchived ?? false
    }
}
