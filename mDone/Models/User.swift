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

    /// Vikunja sends `name` as an empty string for users who never set one,
    /// so empty counts as missing here, not just nil.
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        if let username, !username.isEmpty {
            return username
        }
        return String(localized: "Unknown")
    }

    /// Up to two letters for an avatar: the first letters of the first two
    /// words of the display name, or its first letter when it is one word.
    var initials: String {
        let words = displayName.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}
