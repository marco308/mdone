import EventKit
import Foundation

struct CalendarEvent: Identifiable, Hashable {
    /// Used wherever a calendar's real color is unavailable (deleted calendar, no color set).
    static let fallbackColor = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)

    let id: String // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarIdentifier: String
    let calendarName: String
    let calendarColor: CGColor?
    let location: String?

    init(from ekEvent: EKEvent) {
        id = ekEvent.eventIdentifier
        title = ekEvent.title ?? String(localized: "Untitled")
        startDate = ekEvent.startDate
        endDate = ekEvent.endDate
        isAllDay = ekEvent.isAllDay
        calendarIdentifier = ekEvent.calendar?.calendarIdentifier ?? ""
        calendarName = ekEvent.calendar?.title ?? ""
        calendarColor = ekEvent.calendar?.cgColor
        location = ekEvent.location
    }

    /// Memberwise initialiser used by tests and previews (no EventKit dependency).
    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendarIdentifier: String,
        calendarName: String = "",
        calendarColor: CGColor? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.location = location
    }

    // MARK: - Hashable

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
