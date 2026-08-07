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
                ? "starts \(start.formatted(spokenStyle)), ends \(end.formatted(spokenStyle))"
                : "date range \(lowerBound.formatted(spokenStyle)) to \(upperBound.formatted(spokenStyle))"
            return TaskDateRangeMetadata(
                compactText: (lowerBound ..< upperBound).formatted(intervalStyle),
                accessibilityText: accessibilityText
            )

        case let (start?, nil):
            return TaskDateRangeMetadata(
                compactText: "Starts \(start.formatted(dayStyle))",
                accessibilityText: "starts \(start.formatted(spokenStyle))"
            )

        case let (nil, end?):
            return TaskDateRangeMetadata(
                compactText: "Ends \(end.formatted(dayStyle))",
                accessibilityText: "ends \(end.formatted(spokenStyle))"
            )

        case (nil, nil):
            return nil
        }
    }
}
