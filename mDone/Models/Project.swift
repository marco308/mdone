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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProjectView: Codable, Identifiable {
    let id: Int64
    var title: String
    var projectId: Int64
    var viewKind: String?
    var position: Double?
    var bucketConfigurationMode: Int64?
    var defaultBucketId: Int64?
    var doneBucketId: Int64?
}
