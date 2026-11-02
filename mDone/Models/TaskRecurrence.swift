import Foundation

/// How a task repeats, as Vikunja's `repeat_after` and `repeat_mode` describe it.
///
/// Vikunja stores exactly one instance of a repeating task and advances its due
/// date when the task is completed. It never returns future occurrences and has
/// no endpoint for them, so anything the app shows on a later date is a local
/// estimate. The server stays authoritative: completing the task returns the
/// real next due date, which replaces whatever was projected.
///
/// This type exists so that "does it repeat", "what does it say" and "when does
/// it come back" have one owner instead of being re-derived from the two raw
/// fields at each call site, which is how monthly repeats came to be invisible.
/// Upstream is migrating to RFC 5545 RRULE strings (go-vikunja#2032); when that
/// lands, only `init(repeatAfter:repeatMode:)` and the two projection functions
/// need to change, because every caller is written in terms of this type.
enum TaskRecurrence: Equatable {
    /// `repeat_mode = 0`. Completing the task adds `seconds` to the due date,
    /// repeatedly, until the result is in the future.
    case interval(seconds: Int64)

    /// `repeat_mode = 1`. Completing the task advances the due date by one
    /// calendar month, once, even when the result is still overdue. A day that
    /// does not exist in the next month rolls forward rather than clamping, so
    /// Jan 31 becomes Mar 3. `repeat_after` is ignored in this mode and is
    /// legitimately 0, which is why recurrence cannot be derived from
    /// `repeat_after` alone.
    case monthly

    /// `repeat_mode = 2`. The new due date is the moment of completion plus
    /// `seconds`, so it is unknowable until the user actually completes it.
    case fromCompletion(seconds: Int64)

    /// `nil` when the task does not repeat.
    ///
    /// An unrecognized mode is read as an interval rather than rejected, the
    /// same defensive posture as `VTask.relatedTasks` keeping raw relation
    /// kinds as strings so a value a future server adds cannot break the app.
    init?(repeatAfter: Int64?, repeatMode: Int64?) {
        let seconds = repeatAfter ?? 0
        switch repeatMode ?? 0 {
        case 1:
            self = .monthly
        case 2:
            guard seconds > 0 else { return nil }
            self = .fromCompletion(seconds: seconds)
        default:
            guard seconds > 0 else { return nil }
            self = .interval(seconds: seconds)
        }
    }

    /// Whether future occurrences follow from the schedule alone.
    ///
    /// False for `.fromCompletion`, whose next date depends on when the user
    /// ticks the task off. Projecting it would be a guess about a person rather
    /// than about a schedule, so the app declines to make one.
    var isProjectable: Bool {
        if case .fromCompletion = self { return false }
        return true
    }

    /// How the recurrence reads in a task row.
    var label: String {
        switch self {
        case .monthly:
            return String(localized: "Monthly")
        case let .interval(seconds), let .fromCompletion(seconds):
            let hours = seconds / 3600
            let days = hours / 24
            if days == 1 { return String(localized: "Daily") }
            if days == 7 { return String(localized: "Weekly") }
            if days >= 28, days <= 31 { return String(localized: "Monthly") }
            if days == 365 || days == 366 { return String(localized: "Yearly") }
            if days > 0 { return String(localized: "Every \(days) days") }
            if hours > 0 { return String(localized: "Every \(hours) hours") }
            return String(localized: "Repeating")
        }
    }

    /// The first occurrence strictly after `date`, counting forward from
    /// `dueDate`. `nil` when the recurrence is not projectable, or when a
    /// calendar operation cannot produce a result.
    func nextOccurrence(dueDate: Date, after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .fromCompletion:
            return nil

        case let .interval(seconds):
            guard seconds > 0 else { return nil }
            // Vikunja adds a fixed number of seconds, repeatedly, until the due
            // date is in the future. Doing the same arithmetic in closed form
            // reproduces that exactly, including for a task that is overdue by
            // several intervals. Adding calendar days instead would drift from
            // the server by an hour either side of a daylight saving change.
            let step = TimeInterval(seconds)
            let elapsed = date.timeIntervalSince(dueDate)
            let ratio = (elapsed / step).rounded(.down)
            guard ratio.isFinite, ratio < Self.maxIntervalSteps else { return nil }
            let steps = max(1, Int(ratio) + 1)
            return dueDate.addingTimeInterval(step * TimeInterval(steps))

        case .monthly:
            // Vikunja advances a monthly task with Go's `AddDate(0, 1, 0)`, one
            // month per completion and counted from the stored due date, not the
            // original one. Probed on v2.4.0 and v2.6.0: Jan 31 gives Mar 3, then
            // Apr 3, then May 3, and an overdue task moves a single month even if
            // that is still in the past. Following that chain shows the dates the
            // task will really have, including the ones that look odd.
            var current = dueDate
            for _ in 0 ..< Self.maxMonthlySteps {
                guard let next = Self.addingOneMonth(to: current, calendar: calendar) else { return nil }
                if next > date { return next }
                current = next
            }
            return nil
        }
    }

    /// The occurrences after `dueDate` that fall inside `window`, ascending,
    /// at most one per calendar day.
    ///
    /// One per day is what bounds the work, and the bound comes from what can
    /// be displayed rather than from an arbitrary cap: the calendar grid and
    /// the day list key on a day and can show a task once on it, so a task
    /// repeating every second contributes one date per day of the window
    /// instead of 86400 of them.
    func occurrences(dueDate: Date, in window: Range<Date>, calendar: Calendar) -> [Date] {
        guard isProjectable, window.lowerBound < window.upperBound else { return [] }

        var results: [Date] = []
        var day = calendar.startOfDay(for: window.lowerBound)
        var daysWalked = 0

        while day < window.upperBound, daysWalked < Self.maxProjectedDays {
            daysWalked += 1
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            // Asking for the first occurrence strictly after the instant before
            // this day begins keeps one that lands exactly at midnight, which
            // is where every date-only task sits.
            if let candidate = nextOccurrence(
                dueDate: dueDate,
                after: day.addingTimeInterval(-1),
                calendar: calendar
            ), candidate >= day, candidate < nextDay,
                candidate >= window.lowerBound, candidate < window.upperBound {
                results.append(candidate)
            }
            day = nextDay
        }

        return results
    }

    /// Guards a pathological window, not a supported one. The calendar asks for
    /// a month at a time; anything past a year is a caller mistake and stopping
    /// is better than walking forever.
    private static let maxProjectedDays = 366

    /// How far a monthly chain is followed before giving up: a century, so
    /// only a corrupt date reaches it.
    private static let maxMonthlySteps = 1200

    /// One month later with the same wall-clock day and time, letting a day the
    /// month lacks overflow into the next, as Go's `time.AddDate` does.
    /// `Calendar.date(byAdding:)` clamps instead (Jan 31 to Feb 28), which is
    /// why the components are built by hand.
    private static func addingOneMonth(to date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        guard let month = components.month else { return nil }
        components.month = month + 1
        return calendar.date(from: components)
    }

    /// A ceiling on the closed-form step count, so a corrupt date cannot trap
    /// the `Int` conversion. Far above any real schedule.
    private static let maxIntervalSteps: Double = 1e12
}

extension VTask {
    /// How this task repeats, or `nil` when it does not.
    var recurrence: TaskRecurrence? {
        TaskRecurrence(repeatAfter: repeatAfter, repeatMode: repeatMode)
    }
}
