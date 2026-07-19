import SwiftUI

/// Row size for task rows in the main list views (Inbox, project lists, the
/// calendar day list, and the Mac task list). Mirrors the widgets' Compact /
/// Standard / Large font-size option (`WidgetFontSize`) so the app and widgets
/// stay consistent. Standard is the app's original row size and remains the
/// default; the raw values intentionally match `WidgetFontSize`'s.
enum TaskListDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    static let storageKey = "taskListDensity"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    /// Reads the stored preference, falling back to `.standard` when nothing
    /// has been set or the stored value is unrecognised.
    static func current(defaults: UserDefaults = .standard) -> TaskListDensity {
        guard let stored = defaults.string(forKey: storageKey) else { return .standard }
        return TaskListDensity(rawValue: stored) ?? .standard
    }

    // MARK: Row metrics

    /// Font for the task title.
    var titleFont: Font {
        switch self {
        case .compact: .subheadline
        case .standard: .body
        case .large: .title3
        }
    }

    /// Font for the metadata line (due date, repeat rule).
    var metadataFont: Font {
        switch self {
        case .compact: .caption2
        case .standard: .caption
        case .large: .footnote
        }
    }

    /// Font for the completion-circle symbol.
    var checkboxFont: Font {
        switch self {
        case .compact: .body
        case .standard: .title3
        case .large: .title2
        }
    }

    /// Height of the leading accent bar.
    var accentBarHeight: CGFloat {
        switch self {
        case .compact: 28
        case .standard: 36
        case .large: 44
        }
    }

    /// Vertical padding around the row content.
    var rowVerticalPadding: CGFloat {
        switch self {
        case .compact: 0
        case .standard: 4
        case .large: 8
        }
    }

    /// Spacing between the title and the metadata line.
    var contentSpacing: CGFloat {
        switch self {
        case .compact: 2
        case .standard: 4
        case .large: 6
        }
    }

    /// Maximum number of lines for the task title.
    var titleLineLimit: Int {
        switch self {
        case .compact: 1
        case .standard: 2
        case .large: 2
        }
    }
}
