import EventKit
import Foundation

struct CalendarEvent: Identifiable, Hashable {
    let id: String // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarColor: CGColor?
    let location: String?

    init(from ekEvent: EKEvent) {
        id = ekEvent.eventIdentifier
        title = ekEvent.title ?? "Untitled"
        startDate = ekEvent.startDate
        endDate = ekEvent.endDate
        isAllDay = ekEvent.isAllDay
        calendarName = ekEvent.calendar?.title ?? ""
        calendarColor = ekEvent.calendar?.cgColor
        location = ekEvent.location
    }

    // MARK: - Hashable

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
