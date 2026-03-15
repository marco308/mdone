import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: Int64
    var username: String?
    var name: String?
    var email: String?
    var created: Date?
    var updated: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }

    var displayName: String {
        name ?? username ?? "Unknown"
    }
}
