import Foundation

/// The choices made in the advanced filter sheet.
///
/// Applied locally, on top of the task list `AppState` already holds (every
/// page, done tasks included), rather than by asking the server for a
/// filtered list. The old server round trip replaced `AppState.tasks` with
/// the response, which read one page (Vikunja caps pages at 50, so tasks went
/// missing), fed done tasks into Inbox sections that hide them, and was undone
/// by the next refresh while the toolbar still said a filter was on. Filtering
/// locally keeps the full list intact, works offline, and survives a refresh.
struct AdvancedTaskFilter: Equatable {
    enum DateRange: String, CaseIterable {
        case any
        case overdue
        case today
        case thisWeek
        case thisMonth
        case custom

        var label: String {
            switch self {
            case .any: String(localized: "Any")
            case .overdue: String(localized: "Overdue")
            case .today: String(localized: "Today")
            case .thisWeek: String(localized: "This Week")
            case .thisMonth: String(localized: "This Month")
            case .custom: String(localized: "Custom Range")
            }
        }
    }

    enum Status: String, CaseIterable {
        case any
        case done
        case undone

        var label: String {
            switch self {
            case .any: String(localized: "Any")
            case .done: String(localized: "Done")
            case .undone: String(localized: "Undone")
            }
        }
    }

    /// `nil` is "Any". `.none` means tasks with no priority set.
    var priority: PriorityLevel?
    var dateRange: DateRange = .any
    var customStart: Date = .init()
    var customEnd: Date = .init().addingTimeInterval(7 * 24 * 3600)
    var status: Status = .undone
    var projectId: Int64?

    /// Whether the filter narrows anything. Undone is what the Inbox shows
    /// anyway, so the sheet's defaults count as no filter: opening the sheet
    /// and tapping Apply must not light up the toolbar icon, and Reset must
    /// genuinely clear it.
    var isActive: Bool {
        priority != nil || dateRange != .any || status != .undone || projectId != nil
    }

    func apply(to tasks: [VTask], now: Date = Date(), calendar: Calendar = .current) -> [VTask] {
        guard isActive else { return tasks }
        return tasks.filter { matches($0, now: now, calendar: calendar) }
    }

    func matches(_ task: VTask, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let priority, task.priority != priority.rawValue {
            return false
        }

        switch status {
        case .any: break
        case .done: if !task.done {
                return false
            }
        case .undone: if task.done {
                return false
            }
        }

        if let projectId, task.projectId != projectId {
            return false
        }

        return matchesDateRange(task, now: now, calendar: calendar)
    }

    private func matchesDateRange(_ task: VTask, now: Date, calendar: Calendar) -> Bool {
        // A task with no due date only passes when no range is chosen.
        guard let due = task.effectiveDueDate else { return dateRange == .any }

        let startOfToday = calendar.startOfDay(for: now)
        switch dateRange {
        case .any:
            return true
        case .overdue:
            // Same rule as the Inbox's Overdue section: a date-only task
            // (due at midnight) isn't overdue until its day is over.
            let components = calendar.dateComponents([.hour, .minute], from: due)
            let isDateOnly = (components.hour ?? 0) == 0 && (components.minute ?? 0) == 0
            let deadline = isDateOnly ? endOfDay(due, calendar: calendar) : due
            return deadline < now
        case .today:
            return calendar.isDate(due, inSameDayAs: now)
        case .thisWeek:
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
            return due >= startOfToday && due < weekEnd
        case .thisMonth:
            let monthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? startOfToday
            return due >= startOfToday && due < monthEnd
        case .custom:
            // Whole days at both ends, whichever way round they were picked.
            let first = calendar.startOfDay(for: min(customStart, customEnd))
            let last = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
            return due >= first && due < end
        }
    }

    private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }
}
