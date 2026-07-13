import Foundation

enum TaskRowStyle: String, CaseIterable {
    case standard
    case colorCircle
    case fullCard

    var label: String {
        switch self {
        case .standard: "Standard"
        case .colorCircle: "Colored Circle"
        case .fullCard: "Full Card (Vikunja Style)"
        }
    }
}
