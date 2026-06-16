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

/// Request body for creating a label (`PUT /api/v1/labels`).
/// Snake-casing (`hexColor` -> `hex_color`) is applied by `APIClient`'s encoder.
struct LabelCreateRequest: Encodable {
    var title: String
    var hexColor: String?
}

/// Request body for associating a label with a task
/// (`PUT /api/v1/tasks/{id}/labels`). Snake-cased to `label_id`.
struct LabelTaskRequest: Encodable {
    var labelId: Int64
}
