import EventKit
import Foundation

actor CalendarService {
    private let eventStore = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func fetchEvents(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        return ekEvents.map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Fetch events for a single day
    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return fetchEvents(from: start, to: end)
    }

    /// Fetch events for an entire month (for calendar grid dots)
    func eventsForMonth(_ date: Date) -> [Date: [CalendarEvent]] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [:] }
        let events = fetchEvents(from: monthInterval.start, to: monthInterval.end)

        var grouped: [Date: [CalendarEvent]] = [:]
        for event in events {
            let dayStart = calendar.startOfDay(for: event.startDate)
            grouped[dayStart, default: []].append(event)
        }
        return grouped
    }
}
