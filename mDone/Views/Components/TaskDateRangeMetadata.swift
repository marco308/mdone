import Foundation

/// Display strings for a task's start/end range: a compact line for task rows
/// and a fuller variant (with times) for VoiceOver.
struct TaskDateRangeMetadata: Equatable {
    let compactText: String
    let accessibilityText: String

    static func make(
        startDate: Date?,
        endDate: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> TaskDateRangeMetadata? {
        let timeZone = calendar.timeZone
        let dayStyle = Date.FormatStyle(
            date: .abbreviated, time: .omitted,
            locale: locale, calendar: calendar, timeZone: timeZone
        )
        let spokenStyle = Date.FormatStyle(
            date: .abbreviated, time: .shortened,
            locale: locale, calendar: calendar, timeZone: timeZone
        )

        switch (startDate, endDate) {
        case let (start?, end?):
            let lowerBound = min(start, end)
            let upperBound = max(start, end)
            let intervalStyle = Date.IntervalFormatStyle(
                date: .abbreviated,
                locale: locale, calendar: calendar, timeZone: timeZone
            )
            // Reversed ranges can arrive from imports the editor would reject;
            // describe them neutrally rather than claiming the start comes first.
            let accessibilityText = start <= end
                ? String(
                    localized: "starts \(start.formatted(spokenStyle)), ends \(end.formatted(spokenStyle))",
                    locale: locale
                )
                : String(
                    localized: "date range \(lowerBound.formatted(spokenStyle)) to \(upperBound.formatted(spokenStyle))",
                    locale: locale
                )
            return TaskDateRangeMetadata(
                compactText: (lowerBound ..< upperBound).formatted(intervalStyle),
                accessibilityText: accessibilityText
            )

        case let (start?, nil):
            return TaskDateRangeMetadata(
                compactText: String(localized: "Starts \(start.formatted(dayStyle))", locale: locale),
                accessibilityText: String(localized: "starts \(start.formatted(spokenStyle))", locale: locale)
            )

        case let (nil, end?):
            return TaskDateRangeMetadata(
                compactText: String(localized: "Ends \(end.formatted(dayStyle))", locale: locale),
                accessibilityText: String(localized: "ends \(end.formatted(spokenStyle))", locale: locale)
            )

        case (nil, nil):
            return nil
        }
    }
}
