import Foundation
import SwiftUI

struct VLabel: Codable, Identifiable, Hashable {
    let id: Int64
    var title: String
    var hexColor: String?
    var description: String?
    var createdBy: User?
    var created: Date?
    var updated: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VLabel, rhs: VLabel) -> Bool {
        lhs.id == rhs.id
    }

    var color: Color {
        guard let hexColor, !hexColor.isEmpty else { return .gray }
        return Color(hex: hexColor)
    }
}
