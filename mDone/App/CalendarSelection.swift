import CoreGraphics
import EventKit
import Foundation

/// Lightweight, EventKit-free description of a calendar, suitable for the
/// selection UI and for unit tests.
struct CalendarInfo: Identifiable, Hashable {
    let id: String // EKCalendar.calendarIdentifier
    let title: String
    let color: CGColor?

    init(id: String, title: String, color: CGColor? = nil) {
        self.id = id
        self.title = title
        self.color = color
    }

    init(from ekCalendar: EKCalendar) {
        id = ekCalendar.calendarIdentifier
        title = ekCalendar.title
        color = ekCalendar.cgColor
    }

    // MARK: - Hashable (identity by id only — CGColor isn't Hashable)

    static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Persists the set of calendars the user has chosen to *hide* from mDone.
///
/// We store the hidden set rather than the visible set so that the natural
/// empty default means "show everything", and any calendar the user adds
/// later shows up automatically until they explicitly hide it.
struct HiddenCalendarStore {
    static let storageKey = "hiddenCalendarIdentifiers"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hiddenIdentifiers: Set<String> {
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        return Set(stored)
    }

    func isHidden(_ identifier: String) -> Bool {
        hiddenIdentifiers.contains(identifier)
    }

    /// Hide or unhide a single calendar.
    func setHidden(_ hidden: Bool, for identifier: String) {
        var ids = hiddenIdentifiers
        if hidden {
            ids.insert(identifier)
        } else {
            ids.remove(identifier)
        }
        persist(ids)
    }

    /// Replace the entire hidden set (used by "Show all" / "Hide all").
    func replace(with identifiers: Set<String>) {
        persist(identifiers)
    }

    /// Drop hidden entries for calendars that no longer exist so the set
    /// can't grow unbounded as calendars come and go.
    func prune(toExisting existing: Set<String>) {
        let pruned = hiddenIdentifiers.intersection(existing)
        if pruned != hiddenIdentifiers {
            persist(pruned)
        }
    }

    /// Pure filter: returns only the events whose calendar isn't hidden.
    func visibleEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let hidden = hiddenIdentifiers
        guard !hidden.isEmpty else { return events }
        return events.filter { !hidden.contains($0.calendarIdentifier) }
    }

    private func persist(_ ids: Set<String>) {
        if ids.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(Array(ids).sorted(), forKey: Self.storageKey)
        }
    }
}
