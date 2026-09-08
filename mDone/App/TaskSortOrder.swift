import Foundation

/// How a task list is ordered. `manual` shows the order stored on the server
/// (Vikunja keeps a position per task per view) and is the only mode in which
/// rows can be dragged: in any other mode a drag would be re-sorted away the
/// moment it landed, which is what issue #183 reported. The same rule as
/// Vikunja's own list view, which only enables drag when sorted "Manually".
enum TaskSortOrder: String, CaseIterable, Identifiable {
    case manual
    case dueDate
    case priority
    case title

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .dueDate: String(localized: "Due Date")
        case .priority: String(localized: "Priority")
        case .title: String(localized: "Title")
        }
    }

    /// Manual order has no ascending/descending: it is whatever the user
    /// dragged it into.
    var supportsDirection: Bool {
        self != .manual
    }

    /// Orders `tasks`. Manual returns the input untouched, so callers pass the
    /// list in server (position) order.
    func apply(to tasks: [VTask], ascending: Bool = true) -> [VTask] {
        switch self {
        case .manual:
            tasks
        case .dueDate, .priority, .title:
            tasks.sorted { a, b in
                let result: Bool = switch self {
                case .dueDate:
                    (a.effectiveDueDate ?? .distantFuture) < (b.effectiveDueDate ?? .distantFuture)
                case .priority:
                    a.priority > b.priority
                case .title:
                    a.title.localizedCompare(b.title) == .orderedAscending
                case .manual:
                    true
                }
                return ascending ? result : !result
            }
        }
    }
}

/// Which list a sort preference belongs to. The Inbox is one cross-project
/// list; each project has its own so a project you order by hand stays that
/// way while the rest keep sorting by date.
enum TaskSortScope: Hashable {
    case inbox
    case project(Int64)

    var storageKey: String {
        switch self {
        case .inbox: "taskSort.inbox"
        case let .project(id): "taskSort.project.\(id)"
        }
    }

    /// Manual order only exists inside a project: the Inbox sections are
    /// defined by date and span every project, so a position written there
    /// could never be shown.
    var allowsManual: Bool {
        if case .project = self {
            return true
        }
        return false
    }

    var availableOrders: [TaskSortOrder] {
        TaskSortOrder.allCases.filter { allowsManual || $0 != .manual }
    }
}

/// A sort choice for one list, persisted in `UserDefaults` under the scope's key.
struct TaskSortPreference: Equatable {
    var order: TaskSortOrder
    var ascending: Bool

    /// Due date first, which is what every list showed before manual order
    /// existed, so nobody's list changes on upgrade.
    static let `default` = TaskSortPreference(order: .dueDate, ascending: true)

    /// The result of tapping `order` in the sort menu: picking the current
    /// order again flips the direction, picking another starts it ascending.
    func selecting(_ newOrder: TaskSortOrder) -> TaskSortPreference {
        if newOrder == order, newOrder.supportsDirection {
            return TaskSortPreference(order: order, ascending: !ascending)
        }
        return TaskSortPreference(order: newOrder, ascending: true)
    }

    func apply(to tasks: [VTask]) -> [VTask] {
        order.apply(to: tasks, ascending: ascending)
    }

    // MARK: Persistence

    /// Stored as `"<order>:<asc|desc>"`, one string per scope.
    var storedValue: String {
        "\(order.rawValue):\(ascending ? "asc" : "desc")"
    }

    init(order: TaskSortOrder, ascending: Bool) {
        self.order = order
        self.ascending = ascending
    }

    /// `nil` for anything that isn't a value `storedValue` produced.
    init?(storedValue: String) {
        let parts = storedValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard let order = TaskSortOrder(rawValue: parts.first ?? "") else { return nil }
        let ascending = parts.count < 2 || parts[1] != "desc"
        self.init(order: order, ascending: ascending)
    }

    static func load(for scope: TaskSortScope, defaults: UserDefaults = .standard) -> TaskSortPreference {
        guard let stored = defaults.string(forKey: scope.storageKey),
              let preference = TaskSortPreference(storedValue: stored),
              scope.allowsManual || preference.order != .manual
        else { return .default }
        return preference
    }

    func save(for scope: TaskSortScope, defaults: UserDefaults = .standard) {
        defaults.set(storedValue, forKey: scope.storageKey)
    }
}
